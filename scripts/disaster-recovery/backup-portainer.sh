#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIRECTORY/lib/common.sh"

readonly PORTAINER_ARTIFACT='portainer_data.tar.gz'
readonly PORTAINER_ARCHIVE_IMAGE='alpine:3.20'
PORTAINER_CONTAINER="${PORTAINER_CONTAINER:-portainer}"
PORTAINER_VOLUME="${PORTAINER_VOLUME:-portainer_data}"
BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-teste}"
BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-172.23.1.115}"
BACKUP_REMOTE_ROOT="${BACKUP_REMOTE_ROOT:-/srv/backups/teste-deploy}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-${HOME}/.ssh/id_ed25519_backup_lab}"
readonly PORTAINER_CONTAINER PORTAINER_VOLUME
readonly BACKUP_REMOTE_USER BACKUP_REMOTE_HOST BACKUP_REMOTE_ROOT BACKUP_SSH_KEY

STARTED_AT="$(date '+%s')"
PORTAINER_DIRECTORY=''
ARTIFACT_PATH=''
CHECKSUM_PATH=''
PARTIAL_ARTIFACT_PATH=''
DR_LOG_FILE=''
LOG_FILE_PATH=''
CHECKSUM_VALUE=''
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=0
CHECKSUM_CREATED=0
PARTIAL_CHECKSUM_MAY_EXIST=0
LOCAL_BACKUP_VALID=0
PORTAINER_STOP_ATTEMPTED=0

portainer_is_running() {
    [[ "$(docker inspect --format '{{.State.Running}}' "$PORTAINER_CONTAINER")" == 'true' ]]
}

ensure_portainer_running() {
    if portainer_is_running; then
        PORTAINER_STOP_ATTEMPTED=0
        return 0
    fi

    dr_log 'INFO' "Início do Portainer após parada controlada; container=${PORTAINER_CONTAINER}"
    if ! docker start "$PORTAINER_CONTAINER" 2> >(tee -a "$DR_LOG_FILE" >&2); then
        dr_log 'ERROR' "Não foi possível reiniciar o Portainer; container=${PORTAINER_CONTAINER}"
        return 1
    fi

    if ! portainer_is_running; then
        dr_log 'ERROR' "Portainer não ficou em execução após o restart; container=${PORTAINER_CONTAINER}"
        return 1
    fi

    PORTAINER_STOP_ATTEMPTED=0
    dr_log 'INFO' "Portainer reiniciado; container=${PORTAINER_CONTAINER}"
}

cleanup() {
    local exit_code=$?
    local restart_failed=0

    if (( PORTAINER_STOP_ATTEMPTED )); then
        dr_log 'WARN' 'Cleanup acionado após tentativa de parada do Portainer; verificando reinício obrigatório'
        if ! ensure_portainer_running; then
            restart_failed=1
        fi
    fi

    if (( restart_failed )); then
        exit_code=1
    fi

    if (( exit_code != 0 )); then
        if [[ -n "${PORTAINER_DIRECTORY:-}" && "$LOCAL_BACKUP_VALID" -eq 0 ]]; then
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
                rm -f -- "${PORTAINER_DIRECTORY}/.${PORTAINER_ARTIFACT}.sha256.partial"
            fi
        fi

        if [[ -n "${DR_LOG_FILE:-}" ]]; then
            dr_log 'ERROR' "Backup Portainer FAILED; exit code=${exit_code}; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
        fi
    elif [[ -n "${DR_LOG_FILE:-}" ]]; then
        dr_log 'INFO' "Backup Portainer SUCCESS; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
    fi

    exit "$exit_code"
}

trap cleanup EXIT

DR_ORCHESTRATED="$(dr_resolve_orchestration_mode)" || exit 1
if [[ "$DR_ORCHESTRATED" == '1' && -z "${RUN_ID:-}" ]]; then
    printf 'RUN_ID deve ser fornecido quando DR_ORCHESTRATED=1.\n' >&2
    exit 1
fi
readonly DR_ORCHESTRATED

RUN_ID="$(dr_resolve_run_id)" || exit 1
readonly RUN_ID

if ! dr_mkdir_private "$DR_LOG_ROOT"; then
    printf 'Não foi possível preparar o diretório de logs do backup.\n' >&2
    exit 1
fi

LOG_FILE_PATH="${DR_LOG_ROOT}/${RUN_ID}-portainer.log"
dr_init_log "$LOG_FILE_PATH" || exit 1
DR_LOG_FILE="$LOG_FILE_PATH"
readonly DR_LOG_FILE

dr_log 'INFO' "Pré-validação do backup Portainer iniciada; RUN_ID=${RUN_ID}; orchestrated=${DR_ORCHESTRATED}"

if ! dr_require_commands docker sha256sum stat tee chmod ssh scp; then
    dr_log 'ERROR' 'Dependência obrigatória ausente: docker, sha256sum, stat, tee, chmod, ssh ou scp'
    exit 1
fi

if [[ ! "$PORTAINER_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    dr_log 'ERROR' 'PORTAINER_CONTAINER inválido'
    exit 1
fi

if [[ ! "$PORTAINER_VOLUME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    dr_log 'ERROR' 'PORTAINER_VOLUME inválido'
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

if ! docker inspect "$PORTAINER_CONTAINER" >/dev/null 2>&1; then
    dr_log 'ERROR' "Container Portainer não encontrado: ${PORTAINER_CONTAINER}"
    exit 1
fi

if ! portainer_is_running; then
    dr_log 'ERROR' "Container Portainer não está em execução: ${PORTAINER_CONTAINER}"
    exit 1
fi

if ! docker volume inspect "$PORTAINER_VOLUME" >/dev/null 2>&1; then
    dr_log 'ERROR' "Volume Portainer não encontrado: ${PORTAINER_VOLUME}"
    exit 1
fi

portainer_volume_mounted=0
while IFS='|' read -r mount_type mount_name mount_destination; do
    if [[ "$mount_type" == 'volume' && "$mount_name" == "$PORTAINER_VOLUME" && "$mount_destination" == '/data' ]]; then
        portainer_volume_mounted=1
        break
    fi
done < <(docker inspect --format '{{range .Mounts}}{{printf "%s|%s|%s\n" .Type .Name .Destination}}{{end}}' "$PORTAINER_CONTAINER")

if (( portainer_volume_mounted == 0 )); then
    dr_log 'ERROR' "O volume ${PORTAINER_VOLUME} não está montado em /data no container Portainer"
    exit 1
fi

if ! docker image inspect "$PORTAINER_ARCHIVE_IMAGE" >/dev/null 2>&1; then
    dr_log 'ERROR' "Imagem auxiliar indisponível localmente: ${PORTAINER_ARCHIVE_IMAGE}; obtenha-a antes de executar o backup"
    exit 1
fi

PORTAINER_DIRECTORY="${DR_STAGING_ROOT}/${RUN_ID}/portainer"
ARTIFACT_PATH="${PORTAINER_DIRECTORY}/${PORTAINER_ARTIFACT}"
CHECKSUM_PATH="${PORTAINER_DIRECTORY}/${PORTAINER_ARTIFACT}.sha256"
PARTIAL_ARTIFACT_PATH="${PORTAINER_DIRECTORY}/.${PORTAINER_ARTIFACT}.partial"

if ! dr_mkdir_private "$PORTAINER_DIRECTORY"; then
    dr_log 'ERROR' "Não foi possível preparar o staging Portainer; RUN_ID=${RUN_ID}"
    exit 1
fi

if [[ -e "$ARTIFACT_PATH" || -e "$CHECKSUM_PATH" || -e "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' "Já existem artefatos para RUN_ID=${RUN_ID}; nada será sobrescrito"
    exit 1
fi

dr_log 'INFO' "Backup Portainer iniciado; RUN_ID=${RUN_ID}; container=${PORTAINER_CONTAINER}; volume=${PORTAINER_VOLUME}"
dr_log 'INFO' "Parada controlada do Portainer iniciada; container=${PORTAINER_CONTAINER}"
PORTAINER_STOP_ATTEMPTED=1
if docker stop "$PORTAINER_CONTAINER" \
    > >(tee -a "$DR_LOG_FILE" >&2) \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    stop_exit_code=$?
    dr_log 'ERROR' "Parada controlada do Portainer falhou; exit code=${stop_exit_code}"
    exit "$stop_exit_code"
fi

if portainer_is_running; then
    dr_log 'ERROR' 'O Portainer continuou em execução após docker stop; o archive não será criado'
    exit 1
fi

dr_log 'INFO' "Portainer parado; início da criação do archive do volume somente-leitura; imagem auxiliar=${PORTAINER_ARCHIVE_IMAGE}"
PARTIAL_ARTIFACT_CREATED=1
if docker run --rm \
    --mount "type=volume,src=${PORTAINER_VOLUME},dst=/data,readonly" \
    --entrypoint tar \
    "$PORTAINER_ARCHIVE_IMAGE" \
    -czf - -C /data . \
    > "$PARTIAL_ARTIFACT_PATH" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    archive_exit_code=$?
    dr_log 'ERROR' "Criação do archive Portainer falhou; cleanup reiniciará o Portainer; exit code=${archive_exit_code}"
    exit "$archive_exit_code"
fi

if [[ ! -s "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' 'O archive Portainer foi criado vazio; cleanup reiniciará o Portainer'
    exit 1
fi

mv -- "$PARTIAL_ARTIFACT_PATH" "$ARTIFACT_PATH"
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=1
dr_log 'INFO' "Archive Portainer criado; artefato=${ARTIFACT_PATH}"

if ! ensure_portainer_running; then
    dr_log 'ERROR' 'O archive local foi criado, mas o Portainer não pôde ser reiniciado; o backup será considerado falho'
    exit 1
fi

PARTIAL_CHECKSUM_MAY_EXIST=1
dr_create_sha256 "$PORTAINER_DIRECTORY" "$PORTAINER_ARTIFACT"
PARTIAL_CHECKSUM_MAY_EXIST=0
CHECKSUM_CREATED=1

if ! dr_set_private_permissions "$ARTIFACT_PATH" "$CHECKSUM_PATH"; then
    dr_log 'ERROR' 'Não foi possível restringir as permissões dos artefatos locais Portainer'
    exit 1
fi

read -r CHECKSUM_VALUE _ < "$CHECKSUM_PATH"
dr_log 'INFO' "Checksum SHA-256 criado; sha256=${CHECKSUM_VALUE}; checksum=${CHECKSUM_PATH}"
LOCAL_BACKUP_VALID=1

REMOTE_INCOMPLETE_DIRECTORY="${BACKUP_REMOTE_ROOT}/.incomplete/${RUN_ID}"
REMOTE_PORTAINER_DIRECTORY="${REMOTE_INCOMPLETE_DIRECTORY}/portainer"
REMOTE_FINAL_DIRECTORY="${BACKUP_REMOTE_ROOT}/${RUN_ID}"

dr_log 'INFO' "Início da transferência remota; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_INCOMPLETE_DIRECTORY}"

if dr_remote_prepare_component \
    "$DR_ORCHESTRATED" \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$BACKUP_REMOTE_ROOT" \
    "$RUN_ID" \
    'portainer'; then
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
    "$REMOTE_PORTAINER_DIRECTORY" \
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
    "$REMOTE_PORTAINER_DIRECTORY" \
    "$PORTAINER_ARTIFACT" \
    "${PORTAINER_ARTIFACT}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Não foi possível restringir as permissões remotas; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' 'Permissões remotas restritivas aplicadas aos artefatos Portainer'

if dr_remote_verify_checksum \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_PORTAINER_DIRECTORY" \
    "${PORTAINER_ARTIFACT}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Checksum remoto inválido; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' 'Checksum remoto validado'

if [[ "$DR_ORCHESTRATED" == '1' ]]; then
    dr_log 'INFO' 'Componente Portainer concluído no staging remoto; promoção final será executada pelo orquestrador'
else
    if dr_remote_promote_run \
        "$BACKUP_REMOTE_USER" \
        "$BACKUP_REMOTE_HOST" \
        "$BACKUP_SSH_KEY" \
        "$BACKUP_REMOTE_ROOT" \
        "$RUN_ID" \
        "portainer/${PORTAINER_ARTIFACT}" \
        "portainer/${PORTAINER_ARTIFACT}.sha256"; then
        :
    else
        remote_exit_code=$?
        dr_log 'ERROR' "Falha na promoção remota; diretório incompleto foi preservado; exit code=${remote_exit_code}"
        exit "$remote_exit_code"
    fi

    dr_log 'INFO' "Promoção remota concluída; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_FINAL_DIRECTORY}"
fi

exit 0
