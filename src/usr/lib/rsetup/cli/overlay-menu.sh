# shellcheck shell=bash

# shellcheck source=src/usr/lib/rsetup/cli/edk2-menu.sh
source "/usr/lib/rsetup/cli/edk2-menu.sh"
# shellcheck source=src/usr/lib/rsetup/cli/u-boot-menu.sh
source "/usr/lib/rsetup/cli/u-boot-menu.sh"

ALLOWED_RCONFIG_FUNC+=("overlay")

__overlay_guard() {
    if [[ -n "${U_BOOT_FDT_OVERLAYS:-}" ]]
    then
        echo "Detected 'U_BOOT_FDT_OVERLAYS' in '/etc/default/u-boot'." >&2
        echo "Overlay feature is temporarily disabled until such customization is reverted." >&2
        return 1
    fi

    if [[ -z "${FDT_OVERLAYS_DIR:-}" ]]
    then
        echo "No supported boot loader found, unable to configure overlays." >&2
        return 1
    fi
}

__overlay_resolve() {
    local arg="$1" dir file

    if [[ -z "$arg" ]]
    then
        echo "Empty overlay name is not valid." >&2
        return 1
    fi

    if [[ "$arg" == */* ]]
    then
        dir="$(dirname "$arg")"
        if [[ "$dir" == "." ]]
        then
            dir="$FDT_OVERLAYS_DIR"
        fi
        if [[ "$(realpath "$dir")" != "$(realpath "$FDT_OVERLAYS_DIR")" ]]
        then
            echo "$arg: only overlays within '$FDT_OVERLAYS_DIR' can be managed." >&2
            return 1
        fi
        file="$(basename "${arg%.disabled}")"
    else
        file="${arg%.disabled}"
    fi

    if [[ ! -f "$FDT_OVERLAYS_DIR/$file" && ! -f "$FDT_OVERLAYS_DIR/$file.disabled" && "$file" != *.dtbo ]]
    then
        file="$file.dtbo"
    fi

    if [[ ! -f "$FDT_OVERLAYS_DIR/$file" && ! -f "$FDT_OVERLAYS_DIR/$file.disabled" ]]
    then
        echo "$arg: cannot find such overlay in '$FDT_OVERLAYS_DIR'" >&2
        return 1
    fi

    echo "$file"
}

__validate_overlay_set() {
    (
        msgbox() { echo "$1" >&2; }
        # shellcheck disable=SC2329
        yesno() { return 0; }

        local item title package

        check_overlay_conflict_init
        for item in "$@"
        do
            if ! check_overlay_conflict "$FDT_OVERLAYS_DIR/$item"*
            then
                return 1
            fi

            mapfile -t title < <(parse_dtbo --default-value "file" "title" "$FDT_OVERLAYS_DIR/$item"*)
            mapfile -t package < <(parse_dtbo "package" "$FDT_OVERLAYS_DIR/$item"*)
            if [[ "${package[0]:-null}" != "null" ]] && ! __depends_package "${title[0]}" "${package[@]}"
            then
                echo "Failed to install required packages for '${title[0]}'." >&2
                return 1
            fi
        done
    )
}

load_overlay_setting() {
    if is_u-boot_exist; then
        load_u-boot_setting
    fi

    if is_edk2_exist; then
        load_edk2_setting
    fi
}

update_overlay_entry() {
    local ret=0

    if is_u-boot_exist; then
        u-boot-update || ret=$?
    fi

    if is_edk2_exist; then
        update_entry_overlays || ret=$?
    fi

    return "$ret"
}

disable_overlays() {
    local ret=0

    if is_u-boot_exist; then
        disable_u-boot_overlays || ret=$?
    fi

    if is_edk2_exist; then
        disable_edk2_overlays || ret=$?
    fi

    return "$ret"
}

rebuild_overlays() {
    local version ret=0
    version="${1:-}"

    if is_u-boot_exist; then
        rebuild_u-boot_overlays "$@" || ret=$?
    fi

    if is_edk2_exist "$version"; then
        rebuild_edk2_overlays "$@" || ret=$?
    fi

    return "$ret"
}

enable_overlays() {
    __parameter_count_at_least_check 1 "$@"

    local ret=0

    if is_u-boot_exist; then
        enable_u-boot_overlays "$@" || ret=$?
    fi

    if is_edk2_exist; then
        enable_edk2_overlays "$@" || ret=$?
    fi

    return "$ret"
}

apply_overlays() {
    disable_overlays || return $?

    if (( $# == 0 ))
    then
        update_overlay_entry
    else
        enable_overlays "$@"
    fi
}

__overlay_usage() {
    echo "Usage: rsetup overlay [--enable|--disable] <overlay>..." >&2
    echo "  --enable, -e   enable the given overlays" >&2
    echo "  --disable, -d  disable the given overlays" >&2
    echo "Without either option, each overlay is toggled by its current state." >&2
}

overlay() {
    local mode="toggle" arg resolved path
    local names=() selected=() enabled_items=() disabled_items=() seen=()

    for arg in "$@"
    do
        case "$arg" in
            --enable|-e)
                if [[ "$mode" == "disable" ]]
                then
                    __overlay_usage
                    return "$ERROR_ILLEGAL_PARAMETERS"
                fi
                mode="enable"
                ;;
            --disable|-d)
                if [[ "$mode" == "enable" ]]
                then
                    __overlay_usage
                    return "$ERROR_ILLEGAL_PARAMETERS"
                fi
                mode="disable"
                ;;
            --help|-h)
                __overlay_usage
                return 0
                ;;
            -*)
                echo "$arg: unknown option." >&2
                __overlay_usage
                return "$ERROR_ILLEGAL_PARAMETERS"
                ;;
            *)
                names+=("$arg")
                ;;
        esac
    done

    if (( ${#names[@]} == 0 ))
    then
        __overlay_usage
        return "$ERROR_REQUIRE_PARAMETER"
    fi

    if (( EUID != 0 ))
    then
        echo "Root privileges are required, run this command with sudo." >&2
        return 1
    fi

    load_overlay_setting
    __overlay_guard || return 1

    for path in "$FDT_OVERLAYS_DIR"/*.dtbo
    do
        if [[ -f "$path" ]]
        then
            selected+=("$(basename "$path")")
        fi
    done

    for arg in "${names[@]}"
    do
        resolved="$(__overlay_resolve "$arg")" || return "$ERROR_ILLEGAL_PARAMETERS"

        if __in_array "$resolved" "${seen[@]}" >/dev/null
        then
            continue
        fi
        seen+=("$resolved")

        if [[ "$mode" == "enable" ]]
        then
            if ! __in_array "$resolved" "${selected[@]}" >/dev/null
            then
                selected+=("$resolved")
            fi
            enabled_items+=("$resolved")
        elif [[ "$mode" == "disable" ]]
        then
            __array_remove selected "$resolved"
            disabled_items+=("$resolved")
        elif __in_array "$resolved" "${selected[@]}" >/dev/null
        then
            __array_remove selected "$resolved"
            disabled_items+=("$resolved")
        else
            selected+=("$resolved")
            enabled_items+=("$resolved")
        fi
    done

    if (( ${#selected[@]} != 0 ))
    then
        __validate_overlay_set "${selected[@]}" || return "$?"
    fi
    apply_overlays "${selected[@]}" || return $?

    for resolved in "${disabled_items[@]}"
    do
        printf 'Disabled: %s\n' "$resolved"
    done

    for resolved in "${enabled_items[@]}"
    do
        printf 'Enabled: %s\n' "$resolved"
    done
}
