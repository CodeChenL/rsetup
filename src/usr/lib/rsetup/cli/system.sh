# shellcheck shell=bash

# shellcheck source=src/usr/lib/rsetup/mod/block_helpers.sh
source "/usr/lib/rsetup/mod/block_helpers.sh"
source "/usr/lib/rsetup/mod/hwid.sh"

ALLOWED_RCONFIG_FUNC+=(
    "update_hostname"
    "update_locale"
    "enable_service"
    "disable_service"
    "resize_root"
    "set_thermal_governor"
    "set_led_trigger"
    "set_led_pattern"
    "set_led_netdev"
)

update_bootloader() {
    local pid device
    pid="${1:-$(get_product_id)}"
    __assert_f "/usr/lib/u-boot/$pid/setup.sh"

    device="${2:-$(__get_block_dev)}"

    "/usr/lib/u-boot/$pid/setup.sh" update_bootloader "$device"
}

erase_spinor() {
    local pid
    pid="${1:-$(get_product_id)}"
    __assert_f "/usr/lib/u-boot/$pid/setup.sh"

    "/usr/lib/u-boot/$pid/setup.sh" erase_spinor
}

update_spinor() {
    local pid
    pid="${1:-$(get_product_id)}"
    __assert_f "/usr/lib/u-boot/$pid/setup.sh"

    "/usr/lib/u-boot/$pid/setup.sh" update_spinor
}

erase_emmc_boot() {
    local pid device
    pid="${1:-$(get_product_id)}"
    __assert_f "/usr/lib/u-boot/$pid/setup.sh"

    for device in /dev/mmcblk*boot0
    do
        "/usr/lib/u-boot/$pid/setup.sh" erase_emmc_boot "$device"
    done
}

update_emmc_boot() {
    local pid device
    pid="${1:-$(get_product_id)}"
    __assert_f "/usr/lib/u-boot/$pid/setup.sh"

    for device in /dev/mmcblk*boot0
    do
        "/usr/lib/u-boot/$pid/setup.sh" update_emmc_boot "$device"
    done
}

update_hostname() {
    __parameter_count_check 1 "$@"

    local hostname="$1"

    echo "$hostname" > "/etc/hostname"
    cat << EOF > "/etc/hosts"
127.0.0.1 localhost
127.0.1.1 $hostname

# The following lines are desirable for IPv6 capable hosts
#::1     localhost ip6-localhost ip6-loopback
#fe00::0 ip6-localnet
#ff00::0 ip6-mcastprefix
#ff02::1 ip6-allnodes
#ff02::2 ip6-allrouters
EOF
}

update_locale() {
    __parameter_count_check 1 "$@"

    local locale="$1"
    echo "locales locales/default_environment_locale select $locale" | debconf-set-selections
    echo "locales locales/locales_to_be_generated multiselect $locale UTF-8" | debconf-set-selections
    rm "/etc/locale.gen"
    dpkg-reconfigure --frontend noninteractive locales
}

enable_service() {
    __parameter_count_check 1 "$@"

    local service="$1"
    systemctl enable --now "$service"
}

disable_service() {
    __parameter_count_check 1 "$@"

    local service="$1"
    systemctl disable --now "$service"
}

resize_root() {
    local root_dev filesystem
    root_dev="$(__get_root_dev)"
    filesystem="$(blkid -s TYPE -o value "$root_dev")"

    echo "Resizing root filesystem..."
    case "$filesystem" in
        ext4)
            resize2fs "$root_dev"
            ;;
        btrfs)
            btrfs filesystem resize max /
            ;;
        *)
            echo "Unknown filesystem." >&2
            return 1
            ;;
    esac
}

set_thermal_governor() {
    __parameter_count_check 1 "$@"

    local new_policy="$1" i
    for i in /sys/class/thermal/thermal_zone*/policy
    do
        echo "$new_policy" > "$i"
    done
}

RBUILD_DRIVER_ROOT_PATH="/sys/bus/platform/drivers"

RBUILD_LED_GPIO_DRIVER="leds-gpio"
RBUILD_LED_PWM_DRIVER="leds_pwm"

set_led_trigger() {
    __parameter_count_check 2 "$@"

    local led="$1" trigger="$2" node
    for node in "$RBUILD_DRIVER_ROOT_PATH/$RBUILD_LED_GPIO_DRIVER"/*/leds/"$led"/trigger "$RBUILD_DRIVER_ROOT_PATH/$RBUILD_LED_PWM_DRIVER"/*/leds/"$led"/trigger
    do
        echo "$trigger" > "$node"
    done
}

set_led_pattern() {
    local led="$1" node
    shift

    set_led_trigger "$led" pattern

    for node in "$RBUILD_DRIVER_ROOT_PATH/$RBUILD_LED_GPIO_DRIVER"/*/leds/"$led"/pattern "$RBUILD_DRIVER_ROOT_PATH/$RBUILD_LED_PWM_DRIVER"/*/leds/"$led"/pattern
    do
        echo "$*" > "$node"
    done
}

set_led_netdev() {
    __parameter_count_check 2 "$@"
    local led="$1" netdev="$2"

    set_led_trigger "$led" netdev

    for node in "$RBUILD_DRIVER_ROOT_PATH/$RBUILD_LED_GPIO_DRIVER"/*/leds/"$led"; do
        echo "$netdev" > "$node/device_name"
        echo "1" > "$node/link"
        echo "1" > "$node/tx"
        echo "1" > "$node/rx"
    done
}

set_getty_autologin() {

    local systemd_override="/etc/systemd/system/$1.d"  switch="$2" execstart

    if [[ "$switch" == "ON" ]]
    then
        mkdir -p "$systemd_override"

        if grep -q "serial" <<< "$systemd_override"
        then
            execstart="ExecStart=-/sbin/agetty --autologin radxa --keep-baud 1500000,115200,57600,38400,9600 %I \$TERM"
        else
            execstart="ExecStart=-/sbin/agetty --autologin radxa --noclear %I \$TERM"
        fi
        cat << EOF | tee "$systemd_override"/override.conf >/dev/null
[Service]
ExecStart=
$execstart
EOF
    else
        rm -rf "$systemd_override/override.conf"
    fi

}

set_serial_autologin() {

    local getty switch="$1" available_getty=(serial-getty@ttyAML0.service serial-getty@ttyFIQ0.service)

    for i in "${available_getty[@]}"
    do
        if [[ -z "$(systemctl list-units --no-legend "$i")" ]]
        then
            continue
        else
            getty="$i"
        fi
    done

    if [[ -z "$getty" ]]
    then
        echo "No getty service found." >&2
        return 1
    fi

    set_getty_autologin "$getty" "$switch"
}

set_tty_autologin() {

    local getty switch="$1" available_getty=(getty@tty1.service)

    for i in "${available_getty[@]}"
    do
        if [[ -z "$(systemctl list-units --no-legend "$i")" ]]
        then
            continue
        else
            getty="$i"
        fi
    done

    if [[ -z "$getty" ]]
    then
        echo "No getty service found." >&2
        return 1
    fi

    set_getty_autologin "$getty" "$switch"
}

set_sddm_autologin() {
    local config_dir="/etc/sddm.conf.d" switch="$1"

    if [[ "$switch" == "ON" ]]
    then
        mkdir -p $config_dir
        cat << EOF | tee $config_dir/autologin.conf >/dev/null
[Autologin]
User=radxa
Session=plasma
EOF
    else
        rm -rf "$config_dir/autologin.conf"
    fi
}

set_gdm_autologin() {
    local config_dir="/etc/gdm3" switch="$1"

    if [[ "$switch" == "ON" ]]
    then
        mkdir -p $config_dir
        cat << EOF | tee -a $config_dir/daemon.conf >/dev/null
# Rsetup
[daemon]
AutomaticLogin=radxa
AutomaticLoginEnable=true
# Rsetup

EOF
    else
        sed -i '/^# Rsetup/,/# Rsetup$/d' $config_dir/daemon.conf
    fi
}

set_lightdm_autologin() {
    local config_dir="/etc/lightdm" switch="$1"

    if [[ "$switch" == "ON" ]]
    then
        groupadd autologin
        gpasswd -a radxa autologin
        mkdir -p $config_dir
        cat << EOF | tee -a $config_dir/lightdm.conf >/dev/null
# Rsetup
[Seat:*]
autologin-user=radxa
autologin-session=plasma
# Rsetup

EOF
    else
        sed -i '/^# Rsetup/,/# Rsetup$/d' $config_dir/lightdm.conf
    fi
}
