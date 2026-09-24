#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly CRON_PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
readonly EXECUTOR_USER='lucas-cooperja'
readonly EXECUTOR_HOME="/home/${EXECUTOR_USER}"
readonly CRON_LOG_DIRECTORY='/srv/teste-deploy-data/backup-logs'
readonly CRON_LOG_FILE="${CRON_LOG_DIRECTORY}/cron-backup.log"

export PATH="$CRON_PATH"

if [[ "$(id -un)" != "$EXECUTOR_USER" ]]; then
    printf 'O wrapper de Cron deve ser executado pelo usuário %s.\n' "$EXECUTOR_USER" >&2
    exit 1
fi

if [[ ! -d "$EXECUTOR_HOME" || ! -O "$EXECUTOR_HOME" ]]; then
    printf 'HOME do executor não está disponível ou não pertence ao usuário esperado.\n' >&2
    exit 1
fi

export HOME="$EXECUTOR_HOME"

readonly SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly BACKUP_SCRIPT="${SCRIPT_DIRECTORY}/backup.sh"
readonly MYSQL_BACKUP_DEFAULTS_FILE="${HOME}/.config/teste-deploy/mysql-backup.cnf"
readonly MONGODB_BACKUP_PASSWORD_FILE="${HOME}/.config/teste-deploy/mongodb-backup-password"
readonly BACKUP_SSH_KEY="${HOME}/.ssh/id_ed25519_backup_lab"

if [[ ! -d "$CRON_LOG_DIRECTORY" || -L "$CRON_LOG_DIRECTORY" ]]; then
    printf 'Diretório de logs do Cron indisponível.\n' >&2
    exit 1
fi

if [[ -L "$CRON_LOG_FILE" ]]; then
    printf 'Arquivo de log do Cron não pode ser link simbólico.\n' >&2
    exit 1
fi

if ! : >> "$CRON_LOG_FILE"; then
    printf 'Não foi possível abrir o log operacional do Cron.\n' >&2
    exit 1
fi

if ! chmod 600 -- "$CRON_LOG_FILE"; then
    printf 'Não foi possível aplicar modo 600 ao log operacional do Cron.\n' >&2
    exit 1
fi

exec >> "$CRON_LOG_FILE" 2>&1

require_commands() {
    local command_name

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Dependência obrigatória ausente para o Cron: %s\n' "$command_name"
            return 1
        fi
    done
}

validate_private_file() {
    local file_path="$1"
    local file_mode

    if [[ ! -f "$file_path" || -L "$file_path" || ! -r "$file_path" || ! -O "$file_path" ]]; then
        printf 'Arquivo privado exigido pelo backup não está disponível para o executor.\n'
        return 1
    fi

    file_mode="$(stat -c '%a' -- "$file_path")"
    if [[ "$file_mode" != '600' ]]; then
        printf 'Arquivo privado exigido pelo backup deve ter modo 600.\n'
        return 1
    fi
}

printf '%s [INFO] Wrapper de Cron iniciado; usuário=%s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$EXECUTOR_USER"

if ! require_commands bash docker ssh scp sha256sum flock tar stat chmod; then
    exit 1
fi

if [[ ! -x "$BACKUP_SCRIPT" ]]; then
    printf 'backup.sh não está disponível para execução.\n'
    exit 1
fi

if ! validate_private_file "$MYSQL_BACKUP_DEFAULTS_FILE"; then
    exit 1
fi

if ! validate_private_file "$MONGODB_BACKUP_PASSWORD_FILE"; then
    exit 1
fi

if ! validate_private_file "$BACKUP_SSH_KEY"; then
    exit 1
fi

export MYSQL_BACKUP_DEFAULTS_FILE
export MONGODB_BACKUP_PASSWORD_FILE
export BACKUP_SSH_KEY

# Um Cron deve sempre iniciar uma execução geral nova, não reutilizar variáveis herdadas.
unset RUN_ID DR_ORCHESTRATED

if "$BACKUP_SCRIPT"; then
    printf '%s [INFO] Wrapper de Cron concluído; status=SUCCESS\n' "$(date '+%Y-%m-%d %H:%M:%S%z')"
    exit 0
fi

backup_exit_code=$?
printf '%s [ERROR] Wrapper de Cron concluído; status=FAILED; exit code=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S%z')" \
    "$backup_exit_code"
exit "$backup_exit_code"
