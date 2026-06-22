#!/usr/bin/env bash
# Ensure a Swift 6 toolchain is available for local development.
#
#   macOS : verifies Xcode 16+ / Swift 6 is present (install Xcode from the App Store).
#   Linux : installs the Swift 6.0.3 toolchain + system dependencies (Ubuntu).
#
# Override the install location with SWIFT_INSTALL_DIR (default: /opt/swift).
set -euo pipefail

SWIFT_VERSION="6.0.3"
SWIFT_INSTALL_DIR="${SWIFT_INSTALL_DIR:-/opt/swift}"

have_swift6() {
  command -v swift >/dev/null 2>&1 && swift --version 2>/dev/null | grep -qE "Swift version 6"
}

case "$(uname -s)" in
  Darwin)
    if have_swift6; then
      echo "✓ $(swift --version | head -1) (Xcode toolchain)"; exit 0
    fi
    echo "Swift 6 not found. Install Xcode 16+ from the App Store, then run:"
    echo "  sudo xcode-select -s /Applications/Xcode.app && xcodebuild -runFirstLaunch"
    exit 1
    ;;
  Linux)
    if have_swift6; then echo "✓ $(swift --version | head -1)"; exit 0; fi
    . /etc/os-release 2>/dev/null || true
    if [ "${ID:-}" != "ubuntu" ]; then
      echo "Automated install supports Ubuntu. For other distros see https://www.swift.org/install/"
      exit 1
    fi
    SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    UBU_DOTLESS="${VERSION_ID//./}"   # e.g. 24.04 -> 2404
    URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu${UBU_DOTLESS}/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu${VERSION_ID}.tar.gz"

    echo "Installing Swift ${SWIFT_VERSION} for Ubuntu ${VERSION_ID} -> ${SWIFT_INSTALL_DIR}"
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
      libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev \
      libz3-dev pkg-config tzdata unzip zlib1g-dev
    curl -fSL --retry 3 -o /tmp/swift.tar.gz "$URL"
    $SUDO mkdir -p "$SWIFT_INSTALL_DIR"
    $SUDO tar xzf /tmp/swift.tar.gz -C "$SWIFT_INSTALL_DIR" --strip-components=1
    rm -f /tmp/swift.tar.gz
    echo
    echo "✓ Installed. Add the toolchain to your PATH:"
    echo "    export PATH=${SWIFT_INSTALL_DIR}/usr/bin:\$PATH"
    "${SWIFT_INSTALL_DIR}/usr/bin/swift" --version
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"; exit 1 ;;
esac
