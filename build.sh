#!/usr/bin/env bash
# ==============================================================================
# OpenWrt Build Script for Sercomm JioFiber JCOW414
# Target: EcoNet EN7528HU (Dual-Core MIPS 1004Kc)
# Features: LuCI, USB 3.0/2.0, USB Tethering (RNDIS/NCM/QMI/iOS), USB Storage (NTFS/ext4/exFAT/Ksmbd), LED Triggers
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-${SCRIPT_DIR}/openwrt-source}"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/output}"

UPSTREAM_REPO="https://github.com/openwrt/openwrt.git"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"

echo "=================================================================="
echo "    Building Independent OpenWrt Firmware for JioFiber JCOW414    "
echo "=================================================================="

# Check basic build tools
for tool in git make gcc g++ flex bison gawk python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[-] Error: Required tool '$tool' is not installed."
        echo "    On Ubuntu/Debian, install with:"
        echo "    sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \\"
        echo "    gcc-multilib gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget"
        exit 1
    fi
done

# Step 1: Clone upstream OpenWrt repository with EcoNet/Airoha support
if [ ! -d "${OPENWRT_DIR}/.git" ]; then
    echo "[*] Cloning upstream OpenWrt (${UPSTREAM_BRANCH} branch)..."
    git clone --depth=1 -b "${UPSTREAM_BRANCH}" "${UPSTREAM_REPO}" "${OPENWRT_DIR}"
else
    echo "[*] Upstream OpenWrt repository already exists at ${OPENWRT_DIR}."
fi

cd "${OPENWRT_DIR}"

# Step 1b: Disable the video feed — its qt5 Config.in has recursive Kconfig
# dependencies that corrupt `make defconfig` package resolution.
sed -i.bak 's|^src-git video|#src-git video|' feeds.conf.default 2>/dev/null || true

# Step 2: Update and install package feeds
echo "[*] Updating feeds..."
./scripts/feeds update -a
echo "[*] Installing feeds..."
./scripts/feeds install -a

# Step 2b: Apply GPON xPON port patches (econet-xpon driver, OMCI daemon,
# JCOW414 GPON wiring + feed fixes) on top of upstream main. Must run AFTER
# feeds install: 0002 patches a feeds/packages Makefile.
if [ -d "${SCRIPT_DIR}/patches" ]; then
    for p in "${SCRIPT_DIR}"/patches/*.patch; do
        [ -e "$p" ] || continue
        echo "[*] Applying $(basename "$p")..."
        if git apply --check "$p" 2>/dev/null; then
            git apply "$p"
        elif git apply --reverse --check "$p" 2>/dev/null; then
            echo "[*] $(basename "$p") is already applied."
        elif [ -d "package/kernel/econet-xpon" ]; then
            echo "[*] $(basename "$p") is already integrated in source tree."
        else
            echo "[-] Error: $(basename "$p") does not apply cleanly to this source tree."
            exit 1
        fi
    done
fi

# Step 3: Copy custom filesystem overlays (files/)
if [ -d "${SCRIPT_DIR}/files" ]; then
    echo "[*] Injecting pre-configured overlay files (network, firewall, system, hotplug)..."
    mkdir -p "${OPENWRT_DIR}/files"
    cp -r "${SCRIPT_DIR}/files/"* "${OPENWRT_DIR}/files/"
    chmod +x "${OPENWRT_DIR}/files/etc/hotplug.d/block/"* 2>/dev/null || true
    chmod +x "${OPENWRT_DIR}/files/etc/hotplug.d/net/"* 2>/dev/null || true
    chmod +x "${OPENWRT_DIR}/files/etc/hotplug.d/usb/"* 2>/dev/null || true
    chmod +x "${OPENWRT_DIR}/files/etc/init.d/"* 2>/dev/null || true
fi

# Step 4: Apply seed configuration
echo "[*] Generating .config from seed.config..."
cp "${SCRIPT_DIR}/seed.config" "${OPENWRT_DIR}/.config"
make defconfig
if ! grep -qx 'CONFIG_TARGET_econet_en7528_DEVICE_jiofiber_jcow414=y' .config; then
    echo "[-] Error: defconfig did not select the JCOW414 device."
    exit 1
fi

# Step 5: Download build dependencies
echo "[*] Downloading sources and packages..."
make download -j8

# Step 6: Compile firmware
NPROC=${BUILD_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}
echo "[*] Compiling firmware using ${NPROC} parallel jobs..."
make -j"${NPROC}" || {
    echo "[-] Parallel build failed, attempting single-thread build with verbose logging..."
    make -j1 V=s
}

# Step 7: Collect output images
mkdir -p "${OUTPUT_DIR}"
TRX_FILES=$(find bin/targets/econet/en7528/ -type f -name "*jiofiber_jcow414*.trx" 2>/dev/null || true)

if [ -n "${TRX_FILES}" ]; then
    echo "[+] Build Successful! Copying firmware artifacts to ${OUTPUT_DIR}:"
    for img in ${TRX_FILES}; do
        cp "$img" "${OUTPUT_DIR}/"
        echo "    -> ${OUTPUT_DIR}/$(basename "$img")"
    done
    find bin/targets/econet/en7528/ -maxdepth 1 -type f \
        \( -name '*jiofiber_jcow414*initramfs*.bin' -o -name '*jiofiber_jcow414*sysupgrade.bin' \) \
        -exec cp {} "${OUTPUT_DIR}/" \;
    cd "${OUTPUT_DIR}"
    sha256sum *.trx *.bin > sha256sums 2>/dev/null || shasum -a 256 *.trx *.bin > sha256sums 2>/dev/null
    echo "[+] Checksums generated in ${OUTPUT_DIR}/sha256sums"
else
    echo "[-] Error: No JCOW414 .trx file found in bin/targets/econet/en7528/."
    exit 1
fi

echo "=================================================================="
echo "                       Build Finished                             "
echo "=================================================================="
