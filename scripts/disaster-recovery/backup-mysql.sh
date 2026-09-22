#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIRECTORY/lib/common.sh"

readonly MYSQL_ARTIFACT='teste_deploy.sql'

STARTED_AT="$(date '+%s')"
MYSQL_DIRECTORY=''
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

cleanup() {
    local exit_code=$?

    if (( exit_code != 0 )); then
        if [[ -n "${MYSQL_DIRECTORY:-}" ]]; then
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
                rm -f -- "${MYSQL_DIRECTORY}/.${MYSQL_ARTIFACT}.sha256.partial"
            fi
        fi

        if [[ -n "${DR_LOG_FILE:-}" ]]; then
            dr_log 'ERROR' "Backup MySQL FAILED; exit code=${exit_code}; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
        fi
    elif [[ -n "${DR_LOG_FILE:-}" ]]; then
        dr_log 'INFO' "Backup MySQL SUCCESS; duration=$(dr_elapsed_seconds "$STARTED_AT")s"
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

LOG_FILE_PATH="${DR_LOG_ROOT}/${RUN_ID}-mysql.log"
dr_init_log "$LOG_FILE_PATH" || exit 1
DR_LOG_FILE="$LOG_FILE_PATH"
readonly DR_LOG_FILE

dr_log 'INFO' "Pré-validação do backup MySQL iniciada; RUN_ID=${RUN_ID}"

if ! dr_require_commands mysqldump sha256sum stat tee; then
    dr_log 'ERROR' 'Dependência obrigatória ausente: mysqldump, sha256sum, stat ou tee'
    exit 1
fi

MYSQL_DATABASE="${MYSQL_DATABASE:-teste_deploy}"
if [[ ! "$MYSQL_DATABASE" =~ ^[A-Za-z0-9_]{1,64}$ ]]; then
    dr_log 'ERROR' 'MYSQL_DATABASE deve conter somente letras ASCII, números ou underscore, com até 64 caracteres'
    exit 1
fi
readonly MYSQL_DATABASE

if [[ -z "${MYSQL_BACKUP_DEFAULTS_FILE:-}" ]]; then
    dr_log 'ERROR' 'MYSQL_BACKUP_DEFAULTS_FILE não foi definido'
    exit 1
fi

if [[ ! -f "$MYSQL_BACKUP_DEFAULTS_FILE" || ! -r "$MYSQL_BACKUP_DEFAULTS_FILE" ]]; then
    dr_log 'ERROR' 'MYSQL_BACKUP_DEFAULTS_FILE não é um arquivo legível'
    exit 1
fi

if [[ ! -O "$MYSQL_BACKUP_DEFAULTS_FILE" ]]; then
    dr_log 'ERROR' 'MYSQL_BACKUP_DEFAULTS_FILE deve pertencer ao usuário que executa o backup'
    exit 1
fi

defaults_mode="$(stat -c '%a' -- "$MYSQL_BACKUP_DEFAULTS_FILE")"
if (( (8#${defaults_mode} & 8#077) != 0 )); then
    dr_log 'ERROR' 'MYSQL_BACKUP_DEFAULTS_FILE não pode ter permissões para grupo ou outros'
    exit 1
fi

MYSQL_DIRECTORY="${DR_STAGING_ROOT}/${RUN_ID}/mysql"
ARTIFACT_PATH="${MYSQL_DIRECTORY}/${MYSQL_ARTIFACT}"
CHECKSUM_PATH="${MYSQL_DIRECTORY}/${MYSQL_ARTIFACT}.sha256"
PARTIAL_ARTIFACT_PATH="${MYSQL_DIRECTORY}/.${MYSQL_ARTIFACT}.partial"

if ! dr_mkdir_private "$MYSQL_DIRECTORY"; then
    dr_log 'ERROR' "Não foi possível preparar o staging MySQL; RUN_ID=${RUN_ID}"
    exit 1
fi

if [[ -e "$ARTIFACT_PATH" || -e "$CHECKSUM_PATH" || -e "$PARTIAL_ARTIFACT_PATH" ]]; then
    dr_log 'ERROR' "Já existem artefatos para RUN_ID=${RUN_ID}; nada será sobrescrito"
    exit 1
fi

dr_log 'INFO' "Backup MySQL iniciado; RUN_ID=${RUN_ID}; database=${MYSQL_DATABASE}"
dr_log 'INFO' "Início da etapa mysqldump"

PARTIAL_ARTIFACT_CREATED=1
if mysqldump \
    --defaults-extra-file="$MYSQL_BACKUP_DEFAULTS_FILE" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --no-tablespaces \
    "$MYSQL_DATABASE" \
    > "$PARTIAL_ARTIFACT_PATH" \
    2> >(tee -a "$DR_LOG_FILE" >&2); then
    :
else
    dump_exit_code=$?
    dr_log 'ERROR' "mysqldump falhou; artefato parcial será removido; exit code=${dump_exit_code}"
    exit "$dump_exit_code"
fi

mv -- "$PARTIAL_ARTIFACT_PATH" "$ARTIFACT_PATH"
PARTIAL_ARTIFACT_CREATED=0
ARTIFACT_CREATED=1
dr_log 'INFO' "Fim da etapa mysqldump; artefato=${ARTIFACT_PATH}"

PARTIAL_CHECKSUM_MAY_EXIST=1
dr_create_sha256 "$MYSQL_DIRECTORY" "$MYSQL_ARTIFACT"
PARTIAL_CHECKSUM_MAY_EXIST=0
CHECKSUM_CREATED=1
read -r CHECKSUM_VALUE _ < "$CHECKSUM_PATH"
dr_log 'INFO' "Checksum SHA-256 criado; sha256=${CHECKSUM_VALUE}; checksum=${CHECKSUM_PATH}"

exit 0
