#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIRECTORY/lib/common.sh"

readonly MANIFEST_NAME='manifest.sha256'
readonly MYSQL_ARTIFACT='mysql/teste_deploy.sql'
readonly MONGODB_ARTIFACT='mongodb/teste_deploy_lab.archive'
readonly REDIS_ARTIFACT='redis/redis_data.tar.gz'
readonly LARAVEL_STORAGE_ARTIFACT='laravel-storage/laravel-storage.tar.gz'
readonly PORTAINER_ARTIFACT='portainer/portainer_data.tar.gz'
readonly BACKUP_LOCK_FILE="${DR_STAGING_ROOT}/.backup.lock"
readonly -a MANIFEST_ARTIFACTS=(
    "$MYSQL_ARTIFACT"
    "$MONGODB_ARTIFACT"
    "$REDIS_ARTIFACT"
    "$LARAVEL_STORAGE_ARTIFACT"
    "$PORTAINER_ARTIFACT"
)
readonly -a REMOTE_EXPECTED_FILES=(
    "$MYSQL_ARTIFACT"
    "${MYSQL_ARTIFACT}.sha256"
    "$MONGODB_ARTIFACT"
    "${MONGODB_ARTIFACT}.sha256"
    "$REDIS_ARTIFACT"
    "${REDIS_ARTIFACT}.sha256"
    "$LARAVEL_STORAGE_ARTIFACT"
    "${LARAVEL_STORAGE_ARTIFACT}.sha256"
    "$PORTAINER_ARTIFACT"
    "${PORTAINER_ARTIFACT}.sha256"
    "$MANIFEST_NAME"
)

BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-teste}"
BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-172.23.1.115}"
BACKUP_REMOTE_ROOT="${BACKUP_REMOTE_ROOT:-/srv/backups/teste-deploy}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-${HOME}/.ssh/id_ed25519_backup_lab}"
readonly BACKUP_REMOTE_USER BACKUP_REMOTE_HOST BACKUP_REMOTE_ROOT BACKUP_SSH_KEY

STARTED_AT="$(date '+%s')"
DR_LOG_FILE=''
LOG_FILE_PATH=''
RUN_DIRECTORY=''
REMOTE_INCOMPLETE_DIRECTORY=''
REMOTE_FINAL_DIRECTORY=''
BACKUP_RETENTION_COUNT=''
LOCK_FD=''
LOCK_ACQUIRED=0

cleanup() {
    local exit_code=$?

    if (( exit_code != 0 )); then
        if [[ -n "${DR_LOG_FILE:-}" ]]; then
            dr_log 'ERROR' "Backup geral FAILED; exit code=${exit_code}; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
        fi
    elif [[ -n "${DR_LOG_FILE:-}" ]]; then
        dr_log 'INFO' "Backup geral SUCCESS; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
    fi

    if (( LOCK_ACQUIRED )) && [[ -n "${LOCK_FD:-}" ]]; then
        flock -u "$LOCK_FD" >/dev/null 2>&1 || true
    fi

    exit "$exit_code"
}

trap cleanup EXIT

if [[ "${DR_ORCHESTRATED:-0}" != '0' ]]; then
    printf 'backup.sh não pode ser iniciado com DR_ORCHESTRATED diferente de 0.\n' >&2
    exit 1
fi

RUN_ID="$(dr_resolve_run_id)" || exit 1
readonly RUN_ID

if ! dr_mkdir_private "$DR_LOG_ROOT"; then
    printf 'Não foi possível preparar o diretório de logs do backup geral.\n' >&2
    exit 1
fi

LOG_FILE_PATH="${DR_LOG_ROOT}/${RUN_ID}-backup.log"
dr_init_log "$LOG_FILE_PATH" || exit 1
DR_LOG_FILE="$LOG_FILE_PATH"
readonly DR_LOG_FILE

dr_log 'INFO' "Pré-validação do backup geral iniciada; RUN_ID=${RUN_ID}"

if ! dr_require_commands sha256sum chmod ssh scp flock; then
    dr_log 'ERROR' 'Dependência obrigatória ausente: sha256sum, chmod, ssh, scp ou flock'
    exit 1
fi

BACKUP_RETENTION_COUNT="$(dr_resolve_retention_count)" || {
    dr_log 'ERROR' 'BACKUP_RETENTION_COUNT deve ser um inteiro entre 1 e 365'
    exit 1
}
readonly BACKUP_RETENTION_COUNT

if ! dr_validate_ssh_backup_configuration \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_REMOTE_ROOT" \
    "$BACKUP_SSH_KEY"; then
    dr_log 'ERROR' 'Configuração de transferência SSH inválida ou chave indisponível'
    exit 1
fi

if ! dr_mkdir_private "$DR_STAGING_ROOT"; then
    dr_log 'ERROR' 'Não foi possível preparar o diretório de staging para o lock global'
    exit 1
fi

if ! exec {LOCK_FD}> "$BACKUP_LOCK_FILE"; then
    dr_log 'ERROR' "Não foi possível abrir o arquivo de lock global: ${BACKUP_LOCK_FILE}"
    exit 1
fi

if ! dr_set_private_permissions "$BACKUP_LOCK_FILE"; then
    dr_log 'ERROR' "Não foi possível restringir as permissões do lock global: ${BACKUP_LOCK_FILE}"
    exit 1
fi

if ! flock -n "$LOCK_FD"; then
    dr_log 'ERROR' "Outro backup geral já está em execução; lock indisponível: ${BACKUP_LOCK_FILE}"
    exit 1
fi

LOCK_ACQUIRED=1
dr_log 'INFO' "Lock global adquirido; arquivo=${BACKUP_LOCK_FILE}; retention_count=${BACKUP_RETENTION_COUNT}"

RUN_DIRECTORY="${DR_STAGING_ROOT}/${RUN_ID}"
if [[ -e "$RUN_DIRECTORY" ]]; then
    dr_log 'ERROR' "Staging local já existe para RUN_ID=${RUN_ID}; nada será sobrescrito"
    exit 1
fi

if ! dr_mkdir_private "$RUN_DIRECTORY"; then
    dr_log 'ERROR' "Não foi possível preparar o staging local da execução; RUN_ID=${RUN_ID}"
    exit 1
fi

REMOTE_INCOMPLETE_DIRECTORY="${BACKUP_REMOTE_ROOT}/.incomplete/${RUN_ID}"
REMOTE_FINAL_DIRECTORY="${BACKUP_REMOTE_ROOT}/${RUN_ID}"

dr_log 'INFO' "Preparando staging remoto único; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_INCOMPLETE_DIRECTORY}"
if dr_remote_prepare_orchestrated_run \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$BACKUP_REMOTE_ROOT" \
    "$RUN_ID"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Falha ao preparar o staging remoto único; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

run_component() {
    local component_name="$1"
    local component_script="$2"
    local component_exit_code

    dr_log 'INFO' "Início do componente ${component_name}"

    if env \
        DR_ORCHESTRATED=1 \
        RUN_ID="$RUN_ID" \
        "$component_script"; then
        dr_log 'INFO' "Fim do componente ${component_name}; status=SUCCESS"
        return 0
    fi

    component_exit_code=$?
    dr_log 'ERROR' "Componente ${component_name} falhou; status=FAILED; exit code=${component_exit_code}"
    return "$component_exit_code"
}

run_component 'MySQL' "$SCRIPT_DIRECTORY/backup-mysql.sh"
run_component 'MongoDB' "$SCRIPT_DIRECTORY/backup-mongodb.sh"
run_component 'Redis' "$SCRIPT_DIRECTORY/backup-redis.sh"
run_component 'Laravel storage' "$SCRIPT_DIRECTORY/backup-laravel-storage.sh"
run_component 'Portainer' "$SCRIPT_DIRECTORY/backup-portainer.sh"

dr_log 'INFO' "Criando manifesto global; arquivo=${RUN_DIRECTORY}/${MANIFEST_NAME}"
if dr_create_manifest_sha256 "$RUN_DIRECTORY" "$MANIFEST_NAME" "${MANIFEST_ARTIFACTS[@]}"; then
    :
else
    manifest_exit_code=$?
    dr_log 'ERROR' "Criação do manifesto global falhou; exit code=${manifest_exit_code}"
    exit "$manifest_exit_code"
fi

if ! dr_set_private_permissions "${RUN_DIRECTORY}/${MANIFEST_NAME}"; then
    dr_log 'ERROR' 'Não foi possível restringir as permissões do manifesto local'
    exit 1
fi

dr_log 'INFO' 'Manifesto global criado com modo 600'

if dr_scp_to_remote \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_INCOMPLETE_DIRECTORY" \
    "${RUN_DIRECTORY}/${MANIFEST_NAME}"; then
    :
else
    manifest_exit_code=$?
    dr_log 'ERROR' "Transferência remota do manifesto falhou; diretório incompleto foi preservado; exit code=${manifest_exit_code}"
    exit "$manifest_exit_code"
fi

if dr_remote_set_private_permissions \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_INCOMPLETE_DIRECTORY" \
    "$MANIFEST_NAME"; then
    :
else
    manifest_exit_code=$?
    dr_log 'ERROR' "Não foi possível restringir as permissões remotas do manifesto; diretório incompleto foi preservado; exit code=${manifest_exit_code}"
    exit "$manifest_exit_code"
fi

if dr_remote_verify_checksum \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_INCOMPLETE_DIRECTORY" \
    "$MANIFEST_NAME"; then
    :
else
    manifest_exit_code=$?
    dr_log 'ERROR' "Manifesto remoto inválido; diretório incompleto foi preservado; exit code=${manifest_exit_code}"
    exit "$manifest_exit_code"
fi

dr_log 'INFO' 'Manifesto remoto validado para todos os artefatos'

if dr_remote_promote_run \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$BACKUP_REMOTE_ROOT" \
    "$RUN_ID" \
    "${REMOTE_EXPECTED_FILES[@]}"; then
    :
else
    promotion_exit_code=$?
    dr_log 'ERROR' "Promoção remota final falhou; diretório incompleto foi preservado quando possível; exit code=${promotion_exit_code}"
    exit "$promotion_exit_code"
fi

dr_log 'INFO' "Promoção remota final concluída; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_FINAL_DIRECTORY}"

run_retention() {
    local retention_output=''
    local retention_exit_code=0
    local retention_line

    dr_log 'INFO' "Início da retenção remota; keep_count=${BACKUP_RETENTION_COUNT}"

    if retention_output="$(dr_remote_apply_retention \
        "$BACKUP_REMOTE_USER" \
        "$BACKUP_REMOTE_HOST" \
        "$BACKUP_SSH_KEY" \
        "$BACKUP_REMOTE_ROOT" \
        "$BACKUP_RETENTION_COUNT" 2>&1)"; then
        while IFS= read -r retention_line; do
            [[ -n "$retention_line" ]] && dr_log 'INFO' "Retenção remota: ${retention_line}"
        done <<< "$retention_output"
        dr_log 'INFO' 'Retenção remota concluída'
        return 0
    fi

    retention_exit_code=$?
    dr_log 'WARN' "Retenção remota falhou após a promoção; o novo restore point continua válido; exit code=${retention_exit_code}"
    while IFS= read -r retention_line; do
        [[ -n "$retention_line" ]] && dr_log 'WARN' "Retenção remota: ${retention_line}"
    done <<< "$retention_output"

    return 0
}

run_retention

exit 0
