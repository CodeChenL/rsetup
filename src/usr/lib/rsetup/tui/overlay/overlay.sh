# shellcheck shell=bash

source "/usr/lib/rsetup/mod/hwid.sh"

__overlay_parse_dtbo() {
    dtc -I dtb -O dts "$1" 2>/dev/null | dtc -I dts -O yaml 2>/dev/null | yq -r ".[0].metadata.$2"
}

__overlay_is_compatible() {
    local overlay="$1" dtbo_compatible

    if ! dtbo_compatible="$(__overlay_parse_dtbo "$overlay" "compatible[0]" | xargs -0)"
    then
        return 1
    fi

    for d in $dtbo_compatible
    do
        for p in $(xargs -0 < /sys/firmware/devicetree/base/compatible)
        do
            if [[ "$d" == "$p" ]]
            then
                return
            fi
        done
    done

    return 1
}

__overlay_install() {
    if ! yesno "3rd party overlay could physically damage your system.
In addition, they may miss important metadata for rsetup to recognize correctly.
This means if you ever run 'Manage overlay' function again, your custom overlays
might be disabled, and you will have to manually reenable them.

Are you sure?"
    then
        return
    fi

    local item basename temp
    if ! item="$(fselect "$PWD")"
    then
        return
    fi

    load_u-boot_setting

    basename="$(basename "$item")"
    basename="${basename%.dts}.dtbo"
    temp="$(mktemp)"
    trap 'rm -f $temp' RETURN EXIT

    if ! cpp -E -I "/usr/src/linux-headers-$(uname -r)/include" "$item" "$temp"
    then
        msgbox "Unable to preprocess the source code!"
        return
    fi

    if ! dtc -q -@ -I dts -O dtb -o "$U_BOOT_FDT_OVERLAYS_DIR/$basename" "$item"
    then
        msgbox "Unable to compile the source code!"
        return
    fi

    u-boot-update
}

__overlay_filter() {
    local overlay="$1" temp="$2"

    if ! __overlay_is_compatible "$overlay"
    then
        return
    fi

    exec 100>> "$temp"
    flock 100

    if [[ "$i" == *.dtbo ]]
    then
        echo "$(basename "$overlay") ON" >&100
    elif [[ "$i" == *.dtbo.disabled ]]
    then
        echo "$(basename "$overlay" | sed -E "s/(.*\.dtbo).*/\1/") OFF" >&100
    fi
}

__overlay_manage() {
    echo "Fetching available overlays may take a while, please wait..." >&2
    load_u-boot_setting
    checklist_init

    local temp
    temp="$(mktemp)"
    trap 'rm -f $temp' RETURN EXIT
    for i in "$U_BOOT_FDT_OVERLAYS_DIR"/*.dtbo*
    do
        __overlay_filter "$i" "$temp" &
    done

    wait

    local item=()
    while read -ra item
    do
        checklist_add "${item[@]}"
    done < <(sort "$temp")

    checklist_emptymsg "Unable to find any compatible overlay under $U_BOOT_FDT_OVERLAYS_DIR."
    if ! checklist_show "Please select overlays you want to enable on boot:"
    then
        return
    fi

    disable_overlays

    local item
    for i in "${RSETUP_CHECKLIST_STATE_NEW[@]}"
    do
        item="$(checklist_getitem "$i")"
        mv "$U_BOOT_FDT_OVERLAYS_DIR/$item.disabled" "$U_BOOT_FDT_OVERLAYS_DIR/$item"
    done

    u-boot-update
}

__overlay_reset() {
    rm -rf "$U_BOOT_FDT_OVERLAYS_DIR"
    mkdir -p "$U_BOOT_FDT_OVERLAYS_DIR"
    cp -aR "/usr/lib/linux-image-$(uname -r)/$(get_soc_vendor)/overlays/." "$U_BOOT_FDT_OVERLAYS_DIR"
    disable_overlays
}

__overlay() {
    load_u-boot_setting

    if [[ -n "${U_BOOT_FDT_OVERLAYS:-}" ]]
    then
        msgbox \
"Detected 'U_BOOT_FDT_OVERLAYS' in '/etc/default/u-boot'.
This usually happens when you want to customize your boot process.
To avoid potential conflicts, overlay feature is temporarily disabled until such customization is reverted."
        return
    fi

    menu_init
    menu_add __overlay_manage "Manage overlay"
    menu_add __overlay_install "Install overlay from source"
    menu_add __overlay_reset "Reset installed overlay to kernel's default"
    menu_show "Configure Device Tree Overlay"
}