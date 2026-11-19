#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${ZMK_WORKSPACE:-$REPO_DIR/.west-workspace}"
OUTPUT_DIR="${ZMK_OUTPUT:-$REPO_DIR/build}"
IMAGE="${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
BOARD="${BOARD:-nice_nano_v2}"

prepare_workspace() {
    rm -rf /workspace/config
    mkdir -p /workspace/config
    cp -R --preserve=timestamps /zmk-config/config/. /workspace/config/

    if [[ ! -d /workspace/.west ]]; then
        west init -l /workspace/config
    fi

    west update
    west zephyr-export
}

build_half() {
    local side="$1"
    local shield="corne_${side}"

    west build -s zmk/app -d "/workspace/build/${side}" -b "$BOARD" -- \
        -DZMK_CONFIG=/workspace/config \
        -DSHIELD="$shield" \
        -DZMK_EXTRA_MODULES=/zmk-config

    cp "/workspace/build/${side}/zephyr/zmk.uf2" \
        "/artifacts/${shield}-${BOARD}-zmk.uf2"
}

inside_main() {
    local target="${1:-all}"

    mkdir -p /workspace/.home

    case "$target" in
        shell)
            exec /bin/bash
            ;;
        clean)
            rm -rf /workspace/.west /workspace/zmk /workspace/zephyr \
                /workspace/modules /workspace/tools /workspace/bootloader \
                /workspace/build /workspace/config /artifacts/*
            ;;
        init|update)
            prepare_workspace
            ;;
        left|right)
            prepare_workspace
            build_half "$target"
            ;;
        all)
            prepare_workspace
            build_half left
            build_half right
            ;;
        *)
            echo "Unknown target: $target" >&2
            echo "Usage: build.sh [all|left|right|init|update|shell|clean]" >&2
            return 1
            ;;
    esac
}

host_main() {
    local target="${1:-all}"
    local tty_flags=()

    mkdir -p "$WORKSPACE_DIR" "$OUTPUT_DIR"

    if [[ "$target" == "shell" ]]; then
        tty_flags=(-it)
    fi

    docker run --rm "${tty_flags[@]}" \
        --user "$(id -u):$(id -g)" \
        -e HOME=/workspace/.home \
        -e BOARD="$BOARD" \
        -v "$REPO_DIR:/zmk-config:ro" \
        -v "$WORKSPACE_DIR:/workspace" \
        -v "$OUTPUT_DIR:/artifacts" \
        -w /workspace \
        "$IMAGE" \
        /bin/bash /zmk-config/build.sh --inside "$target"
}

if [[ "${1:-}" == "--inside" ]]; then
    shift
    inside_main "$@"
else
    host_main "$@"
fi
