# shellcheck shell=bash

ALLOWED_RCONFIG_FUNC+=("load_u-boot_setting")

load_u-boot_setting() {
    if [[ ! -e "$ROOT_PATH/etc/default/u-boot" ]]
    then
        touch "$ROOT_PATH/etc/default/u-boot"
    fi

    # shellcheck source=/dev/null
    source "$ROOT_PATH/etc/default/u-boot"

    if [[ -z "${U_BOOT_TIMEOUT:-}" ]]
    then
        if ! grep -q "^U_BOOT_TIMEOUT" "$ROOT_PATH/etc/default/u-boot"
        then
            echo 'U_BOOT_TIMEOUT="10"' >> "$ROOT_PATH/etc/default/u-boot"
        fi
        sed -i "s/^U_BOOT_TIMEOUT=.*/U_BOOT_TIMEOUT=\"10\"/g" "$ROOT_PATH/etc/default/u-boot"
    fi
    if [[ -z "${U_BOOT_PARAMETERS:-}" ]]
    then
        if ! grep -q "^U_BOOT_PARAMETERS" "$ROOT_PATH/etc/default/u-boot"
        then
            echo "U_BOOT_PARAMETERS=\"\$(cat \"\$ROOT_PATH/etc/kernel/cmdline\")\"" >> "$ROOT_PATH/etc/default/u-boot"
        fi
        sed -i "s|^U_BOOT_PARAMETERS=.*|U_BOOT_PARAMETERS=\"\$(cat /etc/kernel/cmdline)\"|g" "$ROOT_PATH/etc/default/u-boot"
    fi

    # shellcheck source=/dev/null
    source "$ROOT_PATH/etc/default/u-boot"

    if [[ -z "${U_BOOT_FDT_OVERLAYS_DIR:-}" ]]
    then
        eval "$(grep "^U_BOOT_FDT_OVERLAYS_DIR" "$(which u-boot-update)")"
        U_BOOT_FDT_OVERLAYS_DIR="${ROOT_PATH}${U_BOOT_FDT_OVERLAYS_DIR}"
    fi
}