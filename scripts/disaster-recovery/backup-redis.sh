#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIRECTORY/lib/common.sh"

readonly REDIS_ARTIFACT='redis_data.tar.gz'
REDIS_CONTAINER="${REDIS_CONTAINER:-teste-deploy-redis}"
REDIS_VOLUME="${REDIS_VOLUME:-redis_data}"
BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-teste}"
BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-172.23.1.115}"
BACKUP_REMOTE_ROOT="${BACKUP_REMOTE_ROOT:-/srv/backups/teste-deploy}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-${HOME}/.ssh/id_ed25519_backup_lab}"
readonly REDIS_CONTAINER REDIS_VOLUME
readonly BACKUP_REMOTE_USER BACKUP_REMOTE_HOST BACKUP_REMOTE_ROOT BACKUP_SSH_KEY

STARTED_AT="$(date '+%s')"
REDIS_DIRECTORY=''
ARTIFACT_PATH=''
CHECKSUM_PATH=''
PARTIAL_ARTIFACT_PATH=''
DR_LOG_FILE=''
LOG_FILE_PATH=''
CHECKSUM_VALUE=''
REDIS_ARCHIVE_IMAGE=''
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=0
CHECKSUM_CREATED=0
PARTIAL_CHECKSUM_MAY_EXIST=0
LOCAL_BACKUP_VALID=0
REDIS_STOP_ATTEMPTED=0

redis_is_running() {
    [[ "$(docker inspect --format '{{.State.Running}}' "$REDIS_CONTAINER")" == 'true' ]]
}

ensure_redis_running() {
    if redis_is_running; then
        REDIS_STOP_ATTEMPTED=0
        return 0
    fi

    dr_log 'INFO' "Início do Redis após parada controlada; container=${REDIS_CONTAINER}"
    if ! docker start "$REDIS_CONTAINER" 2> >(tee -a "$DR_LOG_FILE" >&2); then
        dr_log 'ERROR' "Não foi possível reiniciar o Redis; container=${REDIS_CONTAINER}"
        return 1
    fi

    if ! redis_is_running; then
        dr_log 'ERROR' "Redis não ficou em execução após o restart; container=${REDIS_CONTAINER}"
        return 1
    fi

    REDIS_STOP_ATTEMPTED=0
    dr_log 'INFO' "Redis reiniciado; container=${REDIS_CONTAINER}"
}

cleanup() {
    local exit_code=$?
    local restart_failed=0

    if (( REDIS_STOP_ATTEMPTED )); then
        dr_log 'WARN' 'Cleanup acionado após tentativa de parada do Redis; verificando reinício obrigatório'
        if ! ensure_redis_running; then
            restart_failed=1
        fi
    fi

    if (( restart_failed )); then
        exit_code=1
    fi

    if (( exit_code != 0 )); then
        if [[ -n "${REDIS_DIRECTORY:-}" && "$LOCAL_BACKUP_VALID" -eq 0 ]]; then
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
                rm -f -- "${REDIS_DIRECTORY}/.${REDIS_ARTIFACT}.sha256.partial"
            fi
        fi

        if [[ -n "${DR_LOG_FILE:-}" ]]; then
            dr_log 'ERROR' "Backup Redis FAILED; exit code=${exit_code}; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
        fi
    elif [[ -n "${DR_LOG_FILE:-}" ]]; then
        dr_log 'INFO' "Backup Redis SUCCESS; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
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

LOG_FILE_PATH="${DR_LOG_ROOT}/${RUN_ID}-redis.log"
dr_init_log "$LOG_FILE_PATH" || exit 1
DR_LOG_FILE="$LOG_FILE_PATH"
readonly DR_LOG_FILE

dr_log 'INFO' "Pré-validação do backup Redis iniciada; RUN_ID=${RUN_ID}"

if ! dr_require_commands docker sha256sum stat tee chmod ssh scp; then
    dr_log 'ERROR' 'Dependência obrigatória ausente: docker, sha256sum, stat, tee, chmod, ssh ou scp'
    exit 1
fi

if [[ ! "$REDIS_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    dr_log 'ERROR' 'REDIS_CONTAINER inválido'
    exit 1
fi

if [[ ! "$REDIS_VOLUME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    dr_log 'ERROR' 'REDIS_VOLUME inválido'
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

if ! docker inspect "$REDIS_CONTAINER" >/dev/null 2>&1; then
    dr_log 'ERROR' "Container Redis não encontrado: ${REDIS_CONTAINER}"
    exit 1
fi

if ! redis_is_running; then
    dr_log 'ERROR' "Container Redis não está em execução: ${REDIS_CONTAINER}"
    exit 1
fi

if ! docker volume inspect "$REDIS_VOLUME" >/dev/null 2>&1; then
    dr_log 'ERROR' "Volume Redis não encontrado: ${REDIS_VOLUME}"
    exit 1
fi

redis_volume_mounted=0
while IFS='|' read -r mount_type mount_name mount_destination; do
    if [[ "$mount_type" == 'volume' && "$mount_name" == "$REDIS_VOLUME" && "$mount_destination" == '/data' ]]; then
        redis_volume_mounted=1
        break
    fi
done < <(docker inspect --format '{{range .Mounts}}{{printf "%s|%s|%s\n" .Type .Name .Destination}}{{end}}' "$REDIS_CONTAINER")

if (( redis_volume_mounted == 0 )); then
    dr_log 'ERROR' "O volume ${REDIS_VOLUME} não está montado em /data no container Redis"
    exit 1
fi

REDIS_ARCHIVE_IMAGE="$(docker inspect --format '{{.Config.Image}}' "$REDIS_CONTAINER")"
if [[ -z "$REDIS_ARCHIVE_IMAGE" ]]; then
    dr_log 'ERROR' 'Não foi possível identificar a imagem do container Redis para o container auxiliar de archive'
    exit 1
fi
readonly REDIS_ARCHIVE_IMAGE

REDIS_DIRECTORY="${DR_STAGING_ROOT}/${RUN_ID}/redis"
ARTIFACT_PATH="${REDIS_DIRECTORY}/${REDIS_ARTIFACT}"
CHECKSUM_PATH="${REDIS_DIRECTORY}/${REDIS_ARTIFACT}.sha256"
PARTIAL_ARTIFACT_PATH="${REDIS_DIRECTORY}/.${REDIS_ARTIFACT}.partial"

if ! dr_mkdir_private "$REDIS_DIRECTORY"; then
    dr_log 'ERROR' "Não foi possível preparar o staging Redis; RUN_ID=${RUN_ID}"
    exit 1
fi

if [[ -e "$ARTIFACT_PATH" || -e "$CHECKSUM_PATH" || -e "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' "Já existem artefatos para RUN_ID=${RUN_ID}; nada será sobrescrito"
    exit 1
fi

dr_log 'INFO' "Backup Redis iniciado; RUN_ID=${RUN_ID}; container=${REDIS_CONTAINER}; volume=${REDIS_VOLUME}"
dr_log 'INFO' 'Início da persistência forçada do Redis com SAVE'

if docker exec "$REDIS_CONTAINER" redis-cli SAVE \
    > >(tee -a "$DR_LOG_FILE" >&2) \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    dr_log 'INFO' 'Persistência forçada do Redis concluída'
else
    save_exit_code=$?
    dr_log 'ERROR' "redis-cli SAVE falhou; o Redis não será parado; exit code=${save_exit_code}"
    exit "$save_exit_code"
fi

dr_log 'INFO' "Parada controlada do Redis iniciada; container=${REDIS_CONTAINER}"
REDIS_STOP_ATTEMPTED=1
if docker stop "$REDIS_CONTAINER" \
    > >(tee -a "$DR_LOG_FILE" >&2) \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    stop_exit_code=$?
    dr_log 'ERROR' "Parada controlada do Redis falhou; exit code=${stop_exit_code}"
    exit "$stop_exit_code"
fi

if redis_is_running; then
    dr_log 'ERROR' 'O Redis continuou em execução após docker stop; o archive não será criado'
    exit 1
fi

dr_log 'INFO' 'Redis parado; início da criação do archive do volume somente-leitura'
PARTIAL_ARTIFACT_CREATED=1
if docker run --rm \
    --volumes-from "${REDIS_CONTAINER}:ro" \
    --entrypoint tar \
    "$REDIS_ARCHIVE_IMAGE" \
    -czf - -C /data . \
    > "$PARTIAL_ARTIFACT_PATH" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    archive_exit_code=$?
    dr_log 'ERROR' "Criação do archive Redis falhou; cleanup reiniciará o Redis; exit code=${archive_exit_code}"
    exit "$archive_exit_code"
fi

if [[ ! -s "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' 'O archive Redis foi criado vazio; cleanup reiniciará o Redis'
    exit 1
fi

mv -- "$PARTIAL_ARTIFACT_PATH" "$ARTIFACT_PATH"
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=1
dr_log 'INFO' "Archive Redis criado; artefato=${ARTIFACT_PATH}"

if ! ensure_redis_running; then
    dr_log 'ERROR' 'O archive local foi criado, mas o Redis não pôde ser reiniciado; o backup será considerado falho'
    exit 1
fi

PARTIAL_CHECKSUM_MAY_EXIST=1
dr_create_sha256 "$REDIS_DIRECTORY" "$REDIS_ARTIFACT"
PARTIAL_CHECKSUM_MAY_EXIST=0
CHECKSUM_CREATED=1

if ! dr_set_private_permissions "$ARTIFACT_PATH" "$CHECKSUM_PATH"; then
    dr_log 'ERROR' 'Não foi possível restringir as permissões dos artefatos locais Redis'
    exit 1
fi

read -r CHECKSUM_VALUE _ < "$CHECKSUM_PATH"
dr_log 'INFO' "Checksum SHA-256 criado; sha256=${CHECKSUM_VALUE}; checksum=${CHECKSUM_PATH}"
LOCAL_BACKUP_VALID=1

REMOTE_INCOMPLETE_DIRECTORY="${BACKUP_REMOTE_ROOT}/.incomplete/${RUN_ID}"
REMOTE_REDIS_DIRECTORY="${REMOTE_INCOMPLETE_DIRECTORY}/redis"
REMOTE_FINAL_DIRECTORY="${BACKUP_REMOTE_ROOT}/${RUN_ID}"

dr_log 'INFO' "Início da transferência remota; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_INCOMPLETE_DIRECTORY}"

if dr_remote_prepare_run \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$BACKUP_REMOTE_ROOT" \
    "$RUN_ID" \
    'redis'; then
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
    "$REMOTE_REDIS_DIRECTORY" \
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
    "$REMOTE_REDIS_DIRECTORY" \
    "$REDIS_ARTIFACT" \
    "${REDIS_ARTIFACT}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Não foi possível restringir as permissões remotas; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' 'Permissões remotas restritivas aplicadas aos artefatos Redis'

if dr_remote_verify_checksum \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_REDIS_DIRECTORY" \
    "${REDIS_ARTIFACT}.sha256"; then
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
    "redis/${REDIS_ARTIFACT}" \
    "redis/${REDIS_ARTIFACT}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Falha na promoção remota; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' "Promoção remota concluída; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_FINAL_DIRECTORY}"

exit 0
