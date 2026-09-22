#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIRECTORY/lib/common.sh"

readonly LARAVEL_STORAGE_ARTIFACT='laravel-storage.tar.gz'
LARAVEL_PROJECT_ROOT="${LARAVEL_PROJECT_ROOT:-/home/lucas-cooperja/Documentos/laravel-deploy-test/teste-deploy}"
BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-teste}"
BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-172.23.1.115}"
BACKUP_REMOTE_ROOT="${BACKUP_REMOTE_ROOT:-/srv/backups/teste-deploy}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-${HOME}/.ssh/id_ed25519_backup_lab}"
readonly LARAVEL_PROJECT_ROOT
readonly BACKUP_REMOTE_USER BACKUP_REMOTE_HOST BACKUP_REMOTE_ROOT BACKUP_SSH_KEY

STARTED_AT="$(date '+%s')"
LARAVEL_STORAGE_PRIVATE=''
LARAVEL_STORAGE_DIRECTORY=''
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

cleanup() {
    local exit_code=$?

    if (( exit_code != 0 )); then
        if [[ -n "${LARAVEL_STORAGE_DIRECTORY:-}" && "$LOCAL_BACKUP_VALID" -eq 0 ]]; then
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
                rm -f -- "${LARAVEL_STORAGE_DIRECTORY}/.${LARAVEL_STORAGE_ARTIFACT}.sha256.partial"
            fi
        fi

        if [[ -n "${DR_LOG_FILE:-}" ]]; then
            dr_log 'ERROR' "Backup Laravel storage FAILED; exit code=${exit_code}; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
        fi
    elif [[ -n "${DR_LOG_FILE:-}" ]]; then
        dr_log 'INFO' "Backup Laravel storage SUCCESS; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
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

LOG_FILE_PATH="${DR_LOG_ROOT}/${RUN_ID}-laravel-storage.log"
dr_init_log "$LOG_FILE_PATH" || exit 1
DR_LOG_FILE="$LOG_FILE_PATH"
readonly DR_LOG_FILE

dr_log 'INFO' "Pré-validação do backup Laravel storage iniciada; RUN_ID=${RUN_ID}"

if ! dr_require_commands tar sha256sum stat tee chmod ssh scp; then
    dr_log 'ERROR' 'Dependência obrigatória ausente: tar, sha256sum, stat, tee, chmod, ssh ou scp'
    exit 1
fi

if [[ ! -d "$LARAVEL_PROJECT_ROOT" || ! -r "$LARAVEL_PROJECT_ROOT" || ! -x "$LARAVEL_PROJECT_ROOT" ]]; then
    dr_log 'ERROR' 'LARAVEL_PROJECT_ROOT não existe ou não pode ser acessado pelo usuário executor'
    exit 1
fi

LARAVEL_STORAGE_PRIVATE="${LARAVEL_PROJECT_ROOT}/storage/app/private"
if [[ ! -d "$LARAVEL_STORAGE_PRIVATE" || ! -r "$LARAVEL_STORAGE_PRIVATE" || ! -x "$LARAVEL_STORAGE_PRIVATE" ]]; then
    dr_log 'ERROR' 'storage/app/private não existe ou não pode ser acessado pelo usuário executor'
    exit 1
fi
readonly LARAVEL_STORAGE_PRIVATE

if ! dr_validate_ssh_backup_configuration \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_REMOTE_ROOT" \
    "$BACKUP_SSH_KEY"; then
    dr_log 'ERROR' 'Configuração de transferência SSH inválida ou chave indisponível'
    exit 1
fi

LARAVEL_STORAGE_DIRECTORY="${DR_STAGING_ROOT}/${RUN_ID}/laravel-storage"
ARTIFACT_PATH="${LARAVEL_STORAGE_DIRECTORY}/${LARAVEL_STORAGE_ARTIFACT}"
CHECKSUM_PATH="${LARAVEL_STORAGE_DIRECTORY}/${LARAVEL_STORAGE_ARTIFACT}.sha256"
PARTIAL_ARTIFACT_PATH="${LARAVEL_STORAGE_DIRECTORY}/.${LARAVEL_STORAGE_ARTIFACT}.partial"

if ! dr_mkdir_private "$LARAVEL_STORAGE_DIRECTORY"; then
    dr_log 'ERROR' "Não foi possível preparar o staging Laravel storage; RUN_ID=${RUN_ID}"
    exit 1
fi

if [[ -e "$ARTIFACT_PATH" || -e "$CHECKSUM_PATH" || -e "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' "Já existem artefatos para RUN_ID=${RUN_ID}; nada será sobrescrito"
    exit 1
fi

dr_log 'INFO' "Backup Laravel storage iniciado; RUN_ID=${RUN_ID}; source=${LARAVEL_STORAGE_PRIVATE}"
dr_log 'INFO' 'Início da criação do archive do storage privado'

PARTIAL_ARTIFACT_CREATED=1
if tar -czf "$PARTIAL_ARTIFACT_PATH" -C "$LARAVEL_STORAGE_PRIVATE" . \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    archive_exit_code=$?
    dr_log 'ERROR' "Criação do archive Laravel storage falhou; artefato parcial será removido; exit code=${archive_exit_code}"
    exit "$archive_exit_code"
fi

if [[ ! -s "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' 'O archive Laravel storage foi criado vazio'
    exit 1
fi

mv -- "$PARTIAL_ARTIFACT_PATH" "$ARTIFACT_PATH"
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=1
dr_log 'INFO' "Archive Laravel storage criado; artefato=${ARTIFACT_PATH}"

PARTIAL_CHECKSUM_MAY_EXIST=1
dr_create_sha256 "$LARAVEL_STORAGE_DIRECTORY" "$LARAVEL_STORAGE_ARTIFACT"
PARTIAL_CHECKSUM_MAY_EXIST=0
CHECKSUM_CREATED=1

if ! dr_set_private_permissions "$ARTIFACT_PATH" "$CHECKSUM_PATH"; then
    dr_log 'ERROR' 'Não foi possível restringir as permissões dos artefatos locais Laravel storage'
    exit 1
fi

read -r CHECKSUM_VALUE _ < "$CHECKSUM_PATH"
dr_log 'INFO' "Checksum SHA-256 criado; sha256=${CHECKSUM_VALUE}; checksum=${CHECKSUM_PATH}"
LOCAL_BACKUP_VALID=1

REMOTE_INCOMPLETE_DIRECTORY="${BACKUP_REMOTE_ROOT}/.incomplete/${RUN_ID}"
REMOTE_LARAVEL_STORAGE_DIRECTORY="${REMOTE_INCOMPLETE_DIRECTORY}/laravel-storage"
REMOTE_FINAL_DIRECTORY="${BACKUP_REMOTE_ROOT}/${RUN_ID}"

dr_log 'INFO' "Início da transferência remota; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_INCOMPLETE_DIRECTORY}"

if dr_remote_prepare_run \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$BACKUP_REMOTE_ROOT" \
    "$RUN_ID" \
    'laravel-storage'; then
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
    "$REMOTE_LARAVEL_STORAGE_DIRECTORY" \
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
    "$REMOTE_LARAVEL_STORAGE_DIRECTORY" \
    "$LARAVEL_STORAGE_ARTIFACT" \
    "${LARAVEL_STORAGE_ARTIFACT}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Não foi possível restringir as permissões remotas; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' 'Permissões remotas restritivas aplicadas aos artefatos Laravel storage'

if dr_remote_verify_checksum \
    "$BACKUP_REMOTE_USER" \
    "$BACKUP_REMOTE_HOST" \
    "$BACKUP_SSH_KEY" \
    "$REMOTE_LARAVEL_STORAGE_DIRECTORY" \
    "${LARAVEL_STORAGE_ARTIFACT}.sha256"; then
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
    "laravel-storage/${LARAVEL_STORAGE_ARTIFACT}" \
    "laravel-storage/${LARAVEL_STORAGE_ARTIFACT}.sha256"; then
    :
else
    remote_exit_code=$?
    dr_log 'ERROR' "Falha na promoção remota; diretório incompleto foi preservado; exit code=${remote_exit_code}"
    exit "$remote_exit_code"
fi

dr_log 'INFO' "Promoção remota concluída; destino=${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${REMOTE_FINAL_DIRECTORY}"

exit 0
