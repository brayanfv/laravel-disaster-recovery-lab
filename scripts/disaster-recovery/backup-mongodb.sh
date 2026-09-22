#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIRECTORY/lib/common.sh"

readonly MONGODB_ARCHIVE='teste_deploy_lab.archive'
MONGODB_CONTAINER="${MONGODB_CONTAINER:-teste-deploy-mongodb}"
MONGODB_DATABASE="${MONGODB_DATABASE:-teste_deploy_lab}"
MONGODB_AUTH_DB="${MONGODB_AUTH_DB:-admin}"
MONGODB_BACKUP_USER="${MONGODB_BACKUP_USER:-lab_mongo_root}"
BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-teste}"
BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-172.23.1.115}"
BACKUP_REMOTE_ROOT="${BACKUP_REMOTE_ROOT:-/srv/backups/teste-deploy}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-${HOME}/.ssh/id_ed25519_backup_lab}"
readonly MONGODB_CONTAINER MONGODB_DATABASE MONGODB_AUTH_DB MONGODB_BACKUP_USER
readonly BACKUP_REMOTE_USER BACKUP_REMOTE_HOST BACKUP_REMOTE_ROOT BACKUP_SSH_KEY

mongodb_yaml_double_quote() {
    local value="$1"
    local escaped_value

    if [[ "$value" =~ [[:cntrl:]] ]]; then
        printf 'A senha contém caractere de controle e não pode ser serializada em YAML.\n' >&2
        return 1
    fi

    escaped_value="${value//\\/\\\\}"
    escaped_value="${escaped_value//\"/\\\"}"

    printf '"%s"\n' "$escaped_value"
}

STARTED_AT="$(date '+%s')"
MONGODB_DIRECTORY=''
ARTIFACT_PATH=''
CHECKSUM_PATH=''
PARTIAL_ARTIFACT_PATH=''
DR_LOG_FILE=''
LOG_FILE_PATH=''
CHECKSUM_VALUE=''
MONGO_BACKUP_PASSWORD=''
MONGO_BACKUP_PASSWORD_YAML=''
CONTAINER_TEMP_CONFIG=''
CONTAINER_TEMP_ARCHIVE=''
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=0
CHECKSUM_CREATED=0
PARTIAL_CHECKSUM_MAY_EXIST=0
CONTAINER_CONFIG_MAY_EXIST=0
CONTAINER_ARCHIVE_MAY_EXIST=0
LOCAL_BACKUP_VALID=0

cleanup() {
    local exit_code=$?

    if (( CONTAINER_CONFIG_MAY_EXIST )) && [[ -n "${CONTAINER_TEMP_CONFIG:-}" ]]; then
        if ! docker exec "$MONGODB_CONTAINER" rm -f -- "$CONTAINER_TEMP_CONFIG" >/dev/null 2>&1; then
            if [[ -n "${DR_LOG_FILE:-}" ]]; then
                dr_log 'WARN' 'Não foi possível remover a configuração temporária do MongoDB no container'
            fi
        fi
    fi

    if (( CONTAINER_ARCHIVE_MAY_EXIST )) && [[ -n "${CONTAINER_TEMP_ARCHIVE:-}" ]]; then
        if ! docker exec "$MONGODB_CONTAINER" rm -f -- "$CONTAINER_TEMP_ARCHIVE" >/dev/null 2>&1; then
            if [[ -n "${DR_LOG_FILE:-}" ]]; then
                dr_log 'WARN' 'Não foi possível remover o arquivo temporário do MongoDB no container'
            fi
        fi
    fi

    unset MONGO_BACKUP_PASSWORD MONGO_BACKUP_PASSWORD_YAML || true

    if (( exit_code != 0 )); then
        if [[ -n "${MONGODB_DIRECTORY:-}" && "$LOCAL_BACKUP_VALID" -eq 0 ]]; then
            if (( PARTIAL_ARTIFACT_CREATED )); then
                rm -f -- "$PARTIAL_ARTIFACT_PATH"
            fi

            if (( ARTIFACT_CREATED )); then
                rm -f -- "$ARTIFACT_PATH"
            fi

            if (( CHECKSUM_CREATED )); then
                rm -f -- "$CHECKSUM_PATH"
            fi

            if (( PARTIAL_CHECKSUM_MAY_EXIST )); then
                rm -f -- "${MONGODB_DIRECTORY}/.${MONGODB_ARCHIVE}.sha256.partial"
            fi
        fi

        if [[ -n "${DR_LOG_FILE:-}" ]]; then
            dr_log 'ERROR' "Backup MongoDB FAILED; exit code=${exit_code}; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
        fi
    elif [[ -n "${DR_LOG_FILE:-}" ]]; then
        dr_log 'INFO' "Backup MongoDB SUCCESS; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
    fi

    exit "$exit_code"
}

trap cleanup EXIT

RUN_ID="$(dr_resolve_run_id)" || exit 1
readonly RUN_ID

if ! dr_mkdir_private "$DR_LOG_ROOT"; then
    printf 'Não foi possível preparar o diretório de logs do backup.\n' >&2
    exit 1
fi

LOG_FILE_PATH="${DR_LOG_ROOT}/${RUN_ID}-mongodb.log"
dr_init_log "$LOG_FILE_PATH" || exit 1
DR_LOG_FILE="$LOG_FILE_PATH"
readonly DR_LOG_FILE

dr_log 'INFO' "Pré-validação do backup MongoDB iniciada; RUN_ID=${RUN_ID}"

if ! dr_require_commands docker sha256sum stat tee chmod ssh scp; then
    dr_log 'ERROR' 'Dependência obrigatória ausente: docker, sha256sum, stat, tee, chmod, ssh ou scp'
    exit 1
fi

if [[ ! "$MONGODB_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    dr_log 'ERROR' 'MONGODB_CONTAINER inválido'
    exit 1
fi

if [[ ! "$MONGODB_DATABASE" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
    dr_log 'ERROR' 'MONGODB_DATABASE deve conter somente letras ASCII, números ou underscore, com até 64 caracteres'
    exit 1
fi

if [[ ! "$MONGODB_AUTH_DB" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
    dr_log 'ERROR' 'MONGODB_AUTH_DB deve conter somente letras ASCII, números ou underscore, com até 64 caracteres'
    exit 1
fi

if [[ ! "$MONGODB_BACKUP_USER" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
    dr_log 'ERROR' 'MONGODB_BACKUP_USER deve conter somente letras ASCII, números ou underscore, com até 64 caracteres'
    exit 1
fi

if [[ -z "${MONGODB_BACKUP_PASSWORD_FILE:-}" ]]; then
    dr_log 'ERROR' 'MONGODB_BACKUP_PASSWORD_FILE não foi definido'
    exit 1
fi

if ! dr_validate_private_file "$MONGODB_BACKUP_PASSWORD_FILE"; then
    dr_log 'ERROR' 'MONGODB_BACKUP_PASSWORD_FILE é inválido, indisponível ou possui permissões inseguras'
    exit 1
fi

if ! dr_validate_ssh_backup_configuration \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_REMOTE_ROOT" \
    "$BACKUP_SSH_KEY"; then
    dr_log 'ERROR' 'Configuração de transferência SSH inválida ou chave indisponível'
    exit 1
fi

if ! docker inspect "$MONGODB_CONTAINER" >/dev/null 2>&1; then
    dr_log 'ERROR' "Container MongoDB não encontrado: ${MONGODB_CONTAINER}"
    exit 1
fi

if [[ "$(docker inspect --format '{{.State.Running}}' "$MONGODB_CONTAINER")" != 'true' ]]; then
    dr_log 'ERROR' "Container MongoDB não está em execução: ${MONGODB_CONTAINER}"
    exit 1
fi

MONGODB_DIRECTORY="${DR_STAGING_ROOT}/${RUN_ID}/mongodb"
ARTIFACT_PATH="${MONGODB_DIRECTORY}/${MONGODB_ARCHIVE}"
CHECKSUM_PATH="${MONGODB_DIRECTORY}/${MONGODB_ARCHIVE}.sha256"
PARTIAL_ARTIFACT_PATH="${MONGODB_DIRECTORY}/.${MONGODB_ARCHIVE}.partial"
CONTAINER_TEMP_CONFIG="/tmp/.mongodump-config-${RUN_ID}.yml"
CONTAINER_TEMP_ARCHIVE="/tmp/.${MONGODB_ARCHIVE}.${RUN_ID}.partial"

if ! dr_mkdir_private "$MONGODB_DIRECTORY"; then
    dr_log 'ERROR' "Não foi possível preparar o staging MongoDB; RUN_ID=${RUN_ID}"
    exit 1
fi

if [[ -e "$ARTIFACT_PATH" || -e "$CHECKSUM_PATH" || -e "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' "Já existem artefatos para RUN_ID=${RUN_ID}; nada será sobrescrito"
    exit 1
fi

if docker exec "$MONGODB_CONTAINER" \
    sh -ceu 'test ! -e "$1"; test ! -e "$2"' \
    sh "$CONTAINER_TEMP_CONFIG" "$CONTAINER_TEMP_ARCHIVE" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    collision_exit_code=$?
    dr_log 'ERROR' "Configuração ou archive temporário já existe no container; exit code=${collision_exit_code}"
    exit "$collision_exit_code"
fi

MONGO_BACKUP_PASSWORD="$(< "$MONGODB_BACKUP_PASSWORD_FILE")"
if [[ -z "$MONGO_BACKUP_PASSWORD" ]]; then
    dr_log 'ERROR' 'MONGODB_BACKUP_PASSWORD_FILE está vazio'
    exit 1
fi

if ! MONGO_BACKUP_PASSWORD_YAML="$(mongodb_yaml_double_quote "$MONGO_BACKUP_PASSWORD")"; then
    dr_log 'ERROR' 'Não foi possível serializar a senha para a configuração YAML temporária'
    exit 1
fi

CONTAINER_CONFIG_MAY_EXIST=1
if printf 'password: %s\n' "$MONGO_BACKUP_PASSWORD_YAML" | \
    docker exec -i "$MONGODB_CONTAINER" \
        sh -ceu 'umask 077; cat > "$1"' \
        sh "$CONTAINER_TEMP_CONFIG" \
        2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    config_exit_code=$?
    dr_log 'ERROR' "Não foi possível criar a configuração temporária no container; exit code=${config_exit_code}"
    exit "$config_exit_code"
fi

unset MONGO_BACKUP_PASSWORD MONGO_BACKUP_PASSWORD_YAML

dr_log 'INFO' "Backup MongoDB iniciado; RUN_ID=${RUN_ID}; database=${MONGODB_DATABASE}; container=${MONGODB_CONTAINER}"
dr_log 'INFO' 'Início da etapa mongodump no container'

CONTAINER_ARCHIVE_MAY_EXIST=1
if docker exec "$MONGODB_CONTAINER" \
    sh -ceu 'mongodump --config="$1" --username "$2" --authenticationDatabase "$3" --db "$4" --archive="$5"' \
    sh "$CONTAINER_TEMP_CONFIG" "$MONGODB_BACKUP_USER" "$MONGODB_AUTH_DB" "$MONGODB_DATABASE" "$CONTAINER_TEMP_ARCHIVE" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    dump_exit_code=$?
    dr_log 'ERROR' "mongodump falhou; exit code=${dump_exit_code}"
    exit "$dump_exit_code"
fi

if docker exec "$MONGODB_CONTAINER" rm -f -- "$CONTAINER_TEMP_CONFIG" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    config_cleanup_exit_code=$?
    dr_log 'ERROR' "Não foi possível remover a configuração temporária do container; exit code=${config_cleanup_exit_code}"
    exit "$config_cleanup_exit_code"
fi
CONTAINER_CONFIG_MAY_EXIST=0

dr_log 'INFO' 'Início da cópia do archive do container para o staging local'
PARTIAL_ARTIFACT_CREATED=1
if docker cp "${MONGODB_CONTAINER}:${CONTAINER_TEMP_ARCHIVE}" "$PARTIAL_ARTIFACT_PATH" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    copy_exit_code=$?
    dr_log 'ERROR' "docker cp falhou; artefato parcial será removido; exit code=${copy_exit_code}"
    exit "$copy_exit_code"
fi

if docker exec "$MONGODB_CONTAINER" rm -f -- "$CONTAINER_TEMP_ARCHIVE" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    archive_cleanup_exit_code=$?
    dr_log 'ERROR' "Não foi possível remover o archive temporário do container; exit code=${archive_cleanup_exit_code}"
    exit "$archive_cleanup_exit_code"
fi
CONTAINER_ARCHIVE_MAY_EXIST=0

mv -- "$PARTIAL_ARTIFACT_PATH" "$ARTIFACT_PATH"
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=1
dr_log 'INFO' "Fim da cópia local; artefato=${ARTIFACT_PATH}"

PARTIAL_CHECKSUM_MAY_EXIST=1
dr_create_sha256 "$MONGODB_DIRECTORY" "$MONGODB_ARCHIVE"
PARTIAL_CHECKSUM_MAY_EXIST=0
CHECKSUM_CREATED=1

if ! dr_set_private_permissions "$ARTIFACT_PATH" "$CHECKSUM_PATH"; then
    dr_log 'ERROR' 'Não foi possível restringir as permissões dos artefatos locais MongoDB'
    exit 1
fi

read -r CHECKSUM_VALUE _ < "$CHECKSUM_PATH"
dr_log 'INFO' "Checksum SHA-256 criado; sha256=${CHECKSUM_VALUE}; checksum=${CHECKSUM_PATH}"
LOCAL_BACKUP_VALID=1

REMOTE_INCOMPLETE_DIRECTORY="${BACKUP_REMOTE_ROOT}/.incomplete/${RUN_ID}"
REMOTE_MONGODB_DIRECTORY="${REMOTE_INCOMPLETE_DIRECTORY}/mongodb"
REMOTE_FINAL_DIRECTORY="${BACKUP_REMOTE_ROOT}/${RUN_ID}"

dr_log 'INFO' "Início da transferência remota; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_INCOMPLETE_DIRECTORY}"

if dr_remote_prepare_run \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$BACKUP_REMOTE_ROOT" \
    "$RUN_ID" \
    'mongodb'; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Falha ao preparar o staging remoto; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

if dr_scp_to_remote \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_MONGODB_DIRECTORY" \
    "$ARTIFACT_PATH" \
    "$CHECKSUM_PATH"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Falha na transferência remota; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

if dr_remote_set_private_permissions \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_MONGODB_DIRECTORY" \
    "$MONGODB_ARCHIVE" \
    "${MONGODB_ARCHIVE}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Não foi possível restringir as permissões remotas; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' 'Permissões remotas restritivas aplicadas aos artefatos MongoDB'

if dr_remote_verify_checksum \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_MONGODB_DIRECTORY" \
    "${MONGODB_ARCHIVE}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Checksum remoto inválido; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' 'Checksum remoto validado'

if dr_remote_promote_run \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$BACKUP_REMOTE_ROOT" \
    "$RUN_ID" \
    "mongodb/${MONGODB_ARCHIVE}" \
    "mongodb/${MONGODB_ARCHIVE}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Falha na promoção remota; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' "Promoção remota concluída; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_FINAL_DIRECTORY}"

exit 0
