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

dr_resolve_orchestration_mode() {
    local candidate="${DR_ORCHESTRATED:-0}"

    case "$candidate" in
        0|1)
            printf '%s\n' "$candidate"
            ;;
        *)
            printf 'DR_ORCHESTRATED inválido: use 0 ou 1.\n' >&2
            return 1
            ;;
    esac
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

dr_create_manifest_sha256() {
    local run_directory="$1"
    local manifest_name="$2"
    shift 2
    local temporary_manifest=".${manifest_name}.partial"
    local artifact_path

    if (( $# == 0 )); then
        printf 'O manifesto exige ao menos um artefato.\n' >&2
        return 1
    fi

    dr_validate_relative_path "$manifest_name"
    for artifact_path in "$@"; do
        dr_validate_relative_path "$artifact_path"
    done

    if [[ -e "${run_directory}/${manifest_name}" || -e "${run_directory}/${temporary_manifest}" ]]; then
        printf 'Manifesto local já existe e não será sobrescrito.\n' >&2
        return 1
    fi

    (
        cd -- "$run_directory"

        for artifact_path in "$@"; do
            [[ -f "$artifact_path" ]]
        done

        if ! sha256sum -- "$@" > "$temporary_manifest"; then
            rm -f -- "$temporary_manifest"
            return 1
        fi

        mv -- "$temporary_manifest" "$manifest_name"
    )
}

dr_set_private_permissions() {
    if (( $# == 0 )); then
        printf 'A aplicação de permissões privadas exige ao menos um arquivo.\n' >&2
        return 1
    fi

    chmod 600 -- "$@"
}

dr_validate_private_file() {
    local file_path="$1"
    local file_mode

    if [[ ! -f "$file_path" || ! -r "$file_path" ]]; then
        printf 'Arquivo privado não é legível.\n' >&2
        return 1
    fi

    if [[ ! -O "$file_path" ]]; then
        printf 'Arquivo privado deve pertencer ao usuário executor.\n' >&2
        return 1
    fi

    file_mode="$(stat -c '%a' -- "$file_path")"
    if (( (8#${file_mode} & 8#077) != 0 )); then
        printf 'Arquivo privado não pode ter permissões para grupo ou outros.\n' >&2
        return 1
    fi
}

dr_validate_ssh_backup_configuration() {
    local remote_user="$1"
    local remote_host="$2"
    local remote_root="$3"
    local ssh_key="$4"

    if [[ ! "$remote_user" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        printf 'BACKUP_REMOTE_USER inválido.\n' >&2
        return 1
    fi

    if [[ ! "$remote_host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
        printf 'BACKUP_REMOTE_HOST inválido.\n' >&2
        return 1
    fi

    if [[ ! "$remote_root" =~ ^/[A-Za-z0-9._/-]*$ || "$remote_root" == *'..'* ]]; then
        printf 'BACKUP_REMOTE_ROOT inválido.\n' >&2
        return 1
    fi

    if [[ ! -f "$ssh_key" || ! -r "$ssh_key" ]]; then
        printf 'BACKUP_SSH_KEY não é um arquivo legível.\n' >&2
        return 1
    fi
}

dr_ssh_target() {
    local remote_user="$1"
    local remote_host="$2"

    printf '%s@%s\n' "$remote_user" "$remote_host"
}

dr_validate_relative_path() {
    local relative_path="$1"

    if [[ ! "$relative_path" =~ ^[A-Za-z0-9._/-]+$ || "$relative_path" == /* || "$relative_path" == *'..'* ]]; then
        printf 'Caminho relativo inválido.\n' >&2
        return 1
    fi
}

dr_validate_absolute_path() {
    local absolute_path="$1"

    if [[ ! "$absolute_path" =~ ^/[A-Za-z0-9._/-]*$ || "$absolute_path" == *'..'* ]]; then
        printf 'Caminho absoluto inválido.\n' >&2
        return 1
    fi
}

dr_ssh() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    shift 3

    ssh \
        -i "$ssh_key" \
        -o BatchMode=yes \
        -o IdentitiesOnly=yes \
        -- "$(dr_ssh_target "$remote_user" "$remote_host")" "$@"
}

dr_scp_to_remote() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    local remote_directory="$4"
    shift 4

    scp \
        -i "$ssh_key" \
        -o BatchMode=yes \
        -o IdentitiesOnly=yes \
        -- "$@" "$(dr_ssh_target "$remote_user" "$remote_host"):${remote_directory}/"
}

dr_remote_prepare_run() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    local remote_root="$4"
    local run_id="$5"
    local component_directory="$6"

    dr_validate_relative_path "$component_directory"

    dr_ssh "$remote_user" "$remote_host" "$ssh_key" bash -s -- "$remote_root" "$run_id" "$component_directory" <<'REMOTE_COMMAND'
set -Eeuo pipefail

remote_root="$1"
run_id="$2"
component_directory="$3"
final_directory="${remote_root}/${run_id}"
incomplete_directory="${remote_root}/.incomplete/${run_id}"

if [[ -e "$final_directory" ]]; then
    printf 'Diretório remoto final já existe: %s\n' "$final_directory" >&2
    exit 1
fi

if [[ -e "$incomplete_directory" ]]; then
    printf 'Diretório remoto incompleto já existe: %s\n' "$incomplete_directory" >&2
    exit 1
fi

mkdir -p -- "${incomplete_directory}/${component_directory}"
REMOTE_COMMAND
}

dr_remote_prepare_orchestrated_run() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    local remote_root="$4"
    local run_id="$5"

    dr_ssh "$remote_user" "$remote_host" "$ssh_key" bash -s -- "$remote_root" "$run_id" <<'REMOTE_COMMAND'
set -Eeuo pipefail

remote_root="$1"
run_id="$2"
final_directory="${remote_root}/${run_id}"
incomplete_directory="${remote_root}/.incomplete/${run_id}"

if [[ -e "$final_directory" ]]; then
    printf 'Diretório remoto final já existe: %s\n' "$final_directory" >&2
    exit 1
fi

if [[ -e "$incomplete_directory" ]]; then
    printf 'Diretório remoto incompleto já existe: %s\n' "$incomplete_directory" >&2
    exit 1
fi

mkdir -p -- "$incomplete_directory"
REMOTE_COMMAND
}

dr_remote_prepare_orchestrated_component() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    local remote_root="$4"
    local run_id="$5"
    local component_directory="$6"

    dr_validate_relative_path "$component_directory"

    dr_ssh "$remote_user" "$remote_host" "$ssh_key" bash -s -- "$remote_root" "$run_id" "$component_directory" <<'REMOTE_COMMAND'
set -Eeuo pipefail

remote_root="$1"
run_id="$2"
component_directory="$3"
final_directory="${remote_root}/${run_id}"
incomplete_directory="${remote_root}/.incomplete/${run_id}"
remote_component_directory="${incomplete_directory}/${component_directory}"

[[ ! -e "$final_directory" ]]
[[ -d "$incomplete_directory" ]]

if [[ -e "$remote_component_directory" ]]; then
    printf 'Diretório remoto do componente já existe: %s\n' "$remote_component_directory" >&2
    exit 1
fi

mkdir -- "$remote_component_directory"
REMOTE_COMMAND
}

dr_remote_prepare_component() {
    local orchestrated="$1"
    shift

    case "$orchestrated" in
        0)
            dr_remote_prepare_run "$@"
            ;;
        1)
            dr_remote_prepare_orchestrated_component "$@"
            ;;
        *)
            printf 'Modo de orquestração inválido.\n' >&2
            return 1
            ;;
    esac
}

dr_remote_verify_checksum() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    local remote_directory="$4"
    local checksum_name="$5"

    dr_validate_relative_path "$checksum_name"

    dr_ssh "$remote_user" "$remote_host" "$ssh_key" bash -s -- "$remote_directory" "$checksum_name" <<'REMOTE_COMMAND'
set -Eeuo pipefail

cd -- "$1"
sha256sum -c -- "$2"
REMOTE_COMMAND
}

dr_remote_set_private_permissions() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    local remote_directory="$4"
    shift 4

    if (( $# == 0 )); then
        printf 'A aplicação remota de permissões exige ao menos um arquivo.\n' >&2
        return 1
    fi

    dr_validate_absolute_path "$remote_directory"

    local relative_file
    for relative_file in "$@"; do
        dr_validate_relative_path "$relative_file"
    done

    dr_ssh "$remote_user" "$remote_host" "$ssh_key" bash -s -- "$remote_directory" "$@" <<'REMOTE_COMMAND'
set -Eeuo pipefail

remote_directory="$1"
shift

[[ -d "$remote_directory" ]]

remote_files=()
for relative_file in "$@"; do
    remote_file="${remote_directory}/${relative_file}"
    [[ -f "$remote_file" ]]
    remote_files+=("$remote_file")
done

chmod 600 -- "${remote_files[@]}"
REMOTE_COMMAND
}

dr_remote_promote_run() {
    local remote_user="$1"
    local remote_host="$2"
    local ssh_key="$3"
    local remote_root="$4"
    local run_id="$5"
    shift 5

    if (( $# == 0 )); then
        printf 'A promoção remota exige ao menos um artefato esperado.\n' >&2
        return 1
    fi

    local artifact_path
    for artifact_path in "$@"; do
        dr_validate_relative_path "$artifact_path"
    done

    dr_ssh "$remote_user" "$remote_host" "$ssh_key" bash -s -- "$remote_root" "$run_id" "$@" <<'REMOTE_COMMAND'
set -Eeuo pipefail

remote_root="$1"
run_id="$2"
shift 2
incomplete_directory="${remote_root}/.incomplete/${run_id}"
final_directory="${remote_root}/${run_id}"

[[ -d "$incomplete_directory" ]]
[[ ! -e "$final_directory" ]]

for artifact_path in "$@"; do
    [[ -f "${incomplete_directory}/${artifact_path}" ]]
done

mv -- "$incomplete_directory" "$final_directory"
REMOTE_COMMAND
}

dr_elapsed_seconds() {
    local started_at="$1"
    local finished_at

    finished_at="$(date '+%s')"
    printf '%s\n' "$((finished_at - started_at))"
}
