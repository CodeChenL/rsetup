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
    for node in "$RBUILD_DRIVER_ROOT_PATH/$RBUILD_LED_GPIO_DRIVER"/*/leds/"$led"/pattern "$RBUILD_DRIVER_ROOT_PATH/$RBUILD_LED_PWM_DRIVER"/*/leds/"$led"/pattern
    do
        echo "$*" > "$node"
    done
}
