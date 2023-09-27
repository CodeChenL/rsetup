# shellcheck shell=bash

which() {
    case $1 in
        u-boot-update)
            echo "/usr/sbin/u-boot-update"
            ;;
        *)
            command which "$@"
            ;;
    esac
}

u-boot-update() {
    echo "Running u-boot-update..."
}
