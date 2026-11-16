#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

readonly PACKAGE_FILE="packages/claude-desktop.nix"
readonly FLAKE_ATTR="claude-desktop"
readonly PACKAGES_URL="https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages"

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

flake_path() {
    echo "path:$(pwd -P)"
}

get_current_version() {
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$PACKAGE_FILE" | head -1
}

# Prints "VERSION SHA256" for each release in the apt index, oldest first.
list_releases() {
    curl -fsSL "$PACKAGES_URL" |
        awk '/^Version:/ { version = $2 } /^SHA256:/ { print version, $2 }' |
        sort -V
}

get_latest_version() {
    local version
    version=$(list_releases | tail -1 | cut -d' ' -f1)
    if [ -z "$version" ]; then
        log_error "Failed to fetch the latest version from the apt index"
        exit 1
    fi
    echo "$version"
}

get_release_hash() {
    local version="$1"
    local sha256
    sha256=$(list_releases | awk -v version="$version" '$1 == version { print $2 }' | tail -1)
    if [ -z "$sha256" ]; then
        log_error "Version $version is not in the apt index"
        exit 1
    fi
    nix hash convert --hash-algo sha256 --to sri "$sha256"
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ] || [ ! -f "$PACKAGE_FILE" ]; then
        log_error "flake.nix or $PACKAGE_FILE not found. Run this script from the repository root."
        exit 1
    fi
}

ensure_required_tools_installed() {
    local tool
    for tool in nix perl curl; do
        command -v "$tool" >/dev/null 2>&1 || { log_error "$tool is required but not installed."; exit 1; }
    done
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION  Update to a specific version"
    echo "  --check            Only check for updates (exit 1 when one is available)"
    echo "  --current          Print the packaged version and exit"
    echo "  --latest           Print the latest upstream version and exit"
    echo "  --help             Show this help message"
}

update_package() {
    local version="$1"
    local hash="$2"
    perl -0pi -e "s/version = \"[^\"]+\";/version = \"$version\";/" "$PACKAGE_FILE"
    perl -0pi -e "s|(src = fetchurl \\{.*?hash = )[^;]+;|\${1}\"$hash\";|s" "$PACKAGE_FILE"
}

verify_update() {
    log_info "Building $FLAKE_ATTR"
    nix build "$(flake_path)#$FLAKE_ATTR" --print-build-logs

    # The app needs a display for most commands; check the binary exists.
    test -x "./result/bin/$FLAKE_ATTR"

    log_info "Evaluating flake outputs"
    nix flake check "$(flake_path)" --all-systems --no-build
}

main() {
    ensure_in_repository_root

    local target_version=""
    local mode="update"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) target_version="$2"; shift 2 ;;
            --check) mode="check"; shift ;;
            --current) mode="current"; shift ;;
            --latest) mode="latest"; shift ;;
            --help) print_usage; exit 0 ;;
            *) log_error "Unknown option: $1"; print_usage; exit 1 ;;
        esac
    done

    if [ "$mode" = current ]; then
        get_current_version
        exit 0
    fi

    ensure_required_tools_installed

    if [ "$mode" = latest ]; then
        get_latest_version
        exit 0
    fi

    local current_version latest_version
    current_version=$(get_current_version)
    latest_version=${target_version:-$(get_latest_version)}

    log_info "$FLAKE_ATTR current version: $current_version"
    log_info "$FLAKE_ATTR latest version: $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date"
        exit 0
    fi

    if [ "$mode" = check ]; then
        log_info "Update available: $current_version -> $latest_version"
        exit 1
    fi

    log_info "Updating $FLAKE_ATTR from $current_version to $latest_version"
    update_package "$latest_version" "$(get_release_hash "$latest_version")"

    log_info "Updating flake.lock"
    nix flake update --flake "$(flake_path)"

    verify_update
    git diff --stat "$PACKAGE_FILE" flake.lock 2>/dev/null || true
}

main "$@"
