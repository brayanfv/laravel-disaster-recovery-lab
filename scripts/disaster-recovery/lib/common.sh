#!/usr/bin/env bash

set -Eeuo pipefail

readonly DR_STAGING_ROOT='/srv/teste-deploy-data/backup-staging'
readonly DR_LOG_ROOT='/srv/teste-deploy-data/backup-logs'

dr_now() {
    date '+%Y-%m-%d %H:%M:%S%z'
}

dr_resolve_run_id() {
    local candidate="${RUN_ID:-$(date '+%Y-%m-%d_%H%M%S')}"

    if [[ ! "$candidate" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$ ]]; then
        printf 'RUN_ID inválido: use o formato YYYY-MM-DD_HHMMSS.\n' >&2
        return 1
    fi

    printf '%s\n' "$candidate"
}

dr_require_commands() {
    local command_name

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'Dependência ausente: %s\n' "$command_name" >&2
            return 1
        fi
    done
}

dr_mkdir_private() {
    mkdir -p -- "$1"
}

dr_init_log() {
    local log_file="$1"

    if [[ -e "$log_file" ]]; then
        printf 'Arquivo de log já existe e não será sobrescrito: %s\n' "$log_file" >&2
        return 1
    fi

    : > "$log_file"
}

dr_log() {
    local level="$1"
    shift

    local line
    line="$(dr_now) [$level] $*"

    if [[ -n "${DR_LOG_FILE:-}" ]]; then
        printf '%s\n' "$line" >> "$DR_LOG_FILE"
    fi

    printf '%s\n' "$line" >&2
}

dr_create_sha256() {
    local directory="$1"
    local artifact_name="$2"
    local checksum_name="${artifact_name}.sha256"
    local temporary_checksum=".${checksum_name}.partial"

    (
        cd -- "$directory"
        sha256sum -- "$artifact_name" > "$temporary_checksum"
        mv -- "$temporary_checksum" "$checksum_name"
    )
}

dr_elapsed_seconds() {
    local started_at="$1"
    local finished_at

    finished_at="$(date '+%s')"
    printf '%s\n' "$((finished_at - started_at))"
}
