# Custom OpenWrt for Sercomm JioFiber JCOW414 (EN7528HU)

[![Target Platform](https://img.shields.io/badge/SoC-EcoNet%20EN7528HU%20MIPS%201004Kc-orange.svg)](https://www.airoha.com)
[![Kernel](https://img.shields.io/badge/Kernel-Linux%206.18-green.svg)](https://kernel.org)
[![Flash Protection](https://img.shields.io/badge/Flash-Dual--Bank%20Fail--Safe-brightgreen.svg)](#dual-bank-failsafe--zero-brick-rollback)
[![License](https://img.shields.io/badge/License-GPL--2.0-blue.svg)](LICENSE)

An independent, modern **OpenWrt** firmware build system for the **Sercomm JioFiber JCOW414** (and sibling **JioFiber JCO4032**) Home Gateway router.

> [!NOTE]
> This project is continued from the original **`JFC-Group/jiofiber-jcow414-openwrt`** community repository, expanded with functional GPON (VLAN 1015), automated flash credential provisioning (`jio-gpon-provision`), and kernel 6.18 upstream integration.

This repository tracks the latest upstream OpenWrt platform tree with EcoNet / Airoha support (`Sirherobrine23/openwrt` branch `airoha`, Linux 6.18 kernel), pre-configured with:
* 📱 **Full USB Tethering Support:** Android (RNDIS), Apple iPhone (ipheth / usbmuxd), generic CDC-Ethernet, modern CDC-NCM, Huawei NCM, and Qualcomm QMI / CDC-MBIM 4G/5G modems with plug-and-play network routing.
* 💾 **USB Storage & High-Speed NAS:** Support for NTFS (in-kernel `ntfs3`), ext4, exFAT, and FAT32, automatic drive mounting to `/mnt/`, and low-overhead kernel SMB3 file sharing via `ksmbd-server` + `luci-app-ksmbd` and hard disk idle spindown (`luci-app-hd-idle`).
* 💡 **Intelligent LED Indicators:** Hardware GPHY Ethernet LEDs plus active GPIO RGB status LEDs (`red:status`, `green:status`, `blue:status`) that dynamically pulse and blink based on USB device insertion and tethering throughput.

---

## Hardware Specifications

| Component | Specification | Notes |
| :--- | :--- | :--- |
| **Model** | Sercomm JCOW414 / JioFiber JCO4032 | Reliance Jio Home Gateway |
| **SoC** | EcoNet (Airoha) EN7528HU | Dual-Core MIPS 1004Kc @ 900 MHz (4 VPEs, `mipsel_24kc`) |
| **RAM** | 512 MB DDR3 (SK Hynix) | ~432 MB usable system RAM in OpenWrt |
| **Flash** | 256 MB SPI-NAND + 1 MB SPI-NOR | Micron MT29F2G01 + Puya P25Q80L (Dual-Bank Layout) |
| **Ethernet** | 4x 1 Gbps Gigabit LAN Ports | Switch ports 1–4 auto-bridged to `br-lan` (`192.168.1.1`) |
| **LAN LEDs** | Hardware PHY Driven | Green (1 Gbps Link) and Amber (Activity) |
| **Status LEDs** | Tricolor RGB GPIO | Red (GPIO 27), Green (GPIO 25), Blue (GPIO 23) |
| **Wi-Fi 2.4 GHz** | MediaTek MT7603E (PCIe Bus 0) | 802.11b/g/n 2T2R MIMO |
| **Wi-Fi 5 GHz** | MediaTek MT7613E / MT7663 (PCIe Bus 1) | 802.11a/n/ac Wave 2 MU-MIMO |
| **USB** | 1x USB 3.0 + 1x USB 2.0 | Dual independent 5V VBUS regulators (GPIO 9 & GPIO 11) |
| **Failsafe** | Dual Bank Flash | Bank 1 (`tclinux`) / Bank 2 (`tclinux_slave`) |

---

## Included Features & Package Matrix

### 1. USB Tethering & Cellular Modems
* **Android Phones:** `kmod-usb-net-rndis` enables instant USB tethering when any Android smartphone is plugged in and "USB Tethering" is toggled in phone settings.
* **iPhones & iPads:** `kmod-usb-net-ipheth`, `usbmuxd`, `libimobiledevice`, and `libimobiledevice-utils` handle iOS USB pairing and network tethering.
* **USB Modems / 4G / 5G Dongles:**
  * CDC Ethernet (`kmod-usb-net-cdc-ether`)
  * Modern NCM protocol (`kmod-usb-net-cdc-ncm`, `kmod-usb-net-huawei-cdc-ncm`)
  * Qualcomm QMI protocol (`kmod-usb-net-qmi-wwan`, `uqmi`, `luci-proto-qmi`)
  * MBIM protocol (`kmod-usb-net-cdc-mbim`, `umbim`, `luci-proto-ncm`)
  * Serial / Option fallback (`kmod-usb-serial-option`, `kmod-usb-serial-qualcomm`, `luci-proto-3g`)
  * Automatic mode switching (`usb-modeswitch`)
* **Zero-Touch Routing:** The root overlay pre-configures `tether` (`usb0`), `tether_alt` (`wwan0`), and `tether_eth1` (`eth1`) as DHCP WAN clients and includes them in the firewall's `wan` zone. Internet from tethered devices is automatically distributed to all LAN ports and Wi-Fi clients.

### 2. USB Mass Storage & File Sharing
* **Filesystem Support:** In-kernel `ntfs3` (read-write for Windows hard drives), `kmod-fs-ext4`, `kmod-fs-exfat`, and `kmod-fs-vfat`.
* **Automount Engine:** `/etc/hotplug.d/block/10-mount` detects plugged drives, identifies the filesystem, creates `/mnt/<label>` or `/mnt/<partition>`, and mounts them read/write with UTF-8 encoding.
* **SMB3 Network Sharing:** `ksmbd-server` (the modern, high-performance Linux in-kernel SMB3 server) and `luci-app-ksmbd` provide ultra-fast Samba sharing with virtually zero CPU overhead compared to legacy userspace Samba 4.
* **Power Management:** `luci-app-hd-idle` allows setting spindown timeouts for mechanical external hard drives.

### 3. LED Indicator Logic
* **Green LED (`green:status`):** Solid ON once system has fully booted and services are running.
* **Blue LED (`blue:status`):**
  * Network Activity: Triggers dynamically on network RX/TX traffic whenever USB tethering (`usb0`/`wwan0`) is active.
  * Hardware Plug Detect: Pulses briefly on USB peripheral insertion.
* **Red LED (`red:status`):** Boot / failsafe indicator.

---

## GPON Fiber WAN (xPON Port) 🆕

The JCOW414 is a GPON ONT, and this build now drives the fiber port natively instead of relying on USB tethering as the only WAN. The GPON stack is a port of [OpenWrt PR #24577](https://github.com/openwrt/openwrt/pull/24577) (EN7528 xPON driver + OMCI daemon), carried as [`patches/0001-econet-xpon-jcow414.patch`](patches/0001-econet-xpon-jcow414.patch) on top of upstream OpenWrt main:

* **`kmod-econet-xpon`** — GPON MAC + optical front-end driver (vendor `tclinux_phoenix` GPL source ported to kernel 6.18). Exposes the `ponwan0` WAN netdev with the GEM/T-CONT datapath and the GPON activation state machine.
* **`econet-omcid`** — native userspace OMCI daemon that answers the OLT and programs the datapath (replaces the non-redistributable stock `omci_v2` binary).
* **`econet-xpon-config`** — UCI plumbing (`config econet-xpon`) that loads the driver *with* your ONU identity; deliberately no bare autoload.
* **`luci-app-econet-xpon`** — LuCI page (Network → GPON) for ONU identity provisioning and GPON/OMCI status.
* **`kmod-econet-eth`** — cjdelisle's EcoNet ethernet driver with the PON datapath seam.

### Provisioning your ONU identity (required once)

The driver stays unloaded until a valid ONU serial is set — by design, so the OLT never sees the MediaTek default serial. Get your ONU serial from the sticker on the JCOW414 (or the stock firmware's status page) and set it in the flashed OpenWrt:

```sh
# LuCI: Network -> GPON -> GPON Identity, or via SSH:
uci set econet-xpon.identity.gpon_sn='<ONU-SERIAL>'    # e.g. JSCM12345678
uci set econet-xpon.identity.wan_mac='<WAN-MAC>'       # optional; defaults derived from device MAC
uci commit econet-xpon
reboot
```

After reboot the module loads with your identity; check `cat /sys/class/net/ponwan0/` (or the LuCI GPON page) for the GPON state — **O5** means the OLT has activated the ONU and OMCI provisioning is running. The `pon` interface (DHCP on `ponwan0`, metric 5) is the primary WAN; the USB tethering interfaces remain configured as fallbacks (higher metrics).

> ⚠️ **Status:** the driver reaches O5 + full OMCI handshake on real fiber per the upstream PR (tested on a DASAN H660GM-A against a live OLT). The OMCI daemon currently models a DZS-baseline MIB — Jio's OLT profile (VLAN plan, T-CONT/GEM mapping) may need tuning via the daemon's datapath controls. Report what your OLT does before assuming internet-over-fiber works end-to-end.

---

## How to Build the Firmware

### Option 1: GitHub Actions (Recommended — Zero Setup)
1. Push this directory to your own GitHub repository.
2. Go to the **Actions** tab in GitHub.
3. Select **Build OpenWrt for JioFiber JCOW414** and click **Run workflow**.
4. Once compilation finishes (~35-45 minutes), download the ready-to-flash `.trx` image from the **Artifacts** section!

### Option 2: Build Locally with Docker (macOS / Linux / Windows)
If you have Docker Desktop installed:
```bash
docker compose up --build
```
The compiled image will be saved directly into `./output/`.

### Option 3: Build on Native Ubuntu 22.04+ / WSL2
```bash
# 1. Install prerequisites
sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \
  gcc-multilib gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget

# 2. Run the build script
./build.sh
```
The final flashable `.trx` image will appear in `./output/openwrt-econet-en7528-jiofiber_jcow414-squashfs-tclinux.trx`.

---

## Flashing Instructions (No Disassembly Required)

### Step 1: Root Telnet Access via Downgrade to R2.15

1. Download the official signed Jio R2.15 firmware:
   * **Firmware:** [`SRCMTF1_JCOW414_R2.15.img`](https://raw.githubusercontent.com/gpsarathy/JioFiber-Home-Gateway/master/Firmwares/JCOW414/2.15/SRCMTF1_JCOW414_R2.15.img)
   * **Signature:** [`SRCMTF1_JCOW414_R2.15.sig`](https://raw.githubusercontent.com/gpsarathy/JioFiber-Home-Gateway/master/Firmwares/JCOW414/2.15/SRCMTF1_JCOW414_R2.15.sig)
2. Log into the router at `http://192.168.29.1` (Default: `admin` / `Jiocentrum` or your Wi-Fi password).
3. Navigate to **Administrator** &rarr; **Maintenance** &rarr; **Firmware Upgrade**.
4. Select both files and proceed. Wait ~2 minutes for the router to reboot into R2.15.
5. Log back in, go to **Maintenance** &rarr; **Backup/Restore**, and click **Backup** to download your config file (e.g. `RSVXXXXXXXXXXX_JCOW414.enc`).
6. Run the unlocker tool:
   ```bash
   python3 tools/jiofiber_root_unlocker.py
   ```
   Select your downloaded `.enc` file. The script injects the payload and outputs `backup_root_ready.enc`.
7. In the router web interface, go to **Maintenance** &rarr; **Backup/Restore**, choose `backup_root_ready.enc`, and click **Restore**.
   > ℹ️ *Note: The web UI will show a checksum error. This is normal and expected — the payload runs as root before the checksum check.*
8. Connect to the router via Telnet:
   ```bash
   telnet 192.168.29.1 23
   ```
   * **Username:** `root`
   * **Password:** `password`

---

### Step 2: Flash the Custom OpenWrt Image

1. On your computer, open a terminal in the folder containing your compiled `.trx` file and start a temporary web server:
   ```bash
   python3 -m http.server 8000
   ```
2. In the router's Telnet shell, download the firmware into RAM:
   ```sh
   cd /tmp
   # Replace 192.168.29.X with your computer's IP
   wget http://192.168.29.X:8000/openwrt-econet-en7528-jiofiber_jcow414-squashfs-tclinux.trx -O openwrt.trx
   ```
3. Flash the image into **Bank 1 (`tclinux`)**:
   ```sh
   # -f force flag is required to bypass stock TRX header check
   mtd -f write /tmp/openwrt.trx tclinux
   ```
4. Swap the boot flag to launch Bank 1:
   ```sh
   /usr/bin/sys bootflag swap
   reboot
   ```

5. Connect an Ethernet cable to LAN Port 1 and open:
   ```
   http://192.168.1.1
   ```
   Log into the OpenWrt LuCI Dashboard! 🎉

---

## Dual-Bank Failsafe & Zero-Brick Rollback

The Sercomm JCOW414 flash partition layout contains two distinct firmware banks:
* **Bank 1 (`tclinux` / `mtd4`):** OpenWrt (Flashing target)
* **Bank 2 (`tclinux_slave` / `mtd7`):** Stock Jio R2.15 (Untouched recovery bank)

To instantly return to stock Jio firmware at any time:
1. Log into OpenWrt via SSH:
   ```bash
   ssh root@192.168.1.1
   ```
2. If the stock bootflag utility is not accessible in userland, you can swap the boot partition back or trigger the failsafe rollback:
   ```bash
   # Re-swap boot partition flag or reboot into Bank 2
   reboot
   ```
*(The stock EcoNet bootloader automatically falls back to Bank 2 if Bank 1 fails verification).*

---

## Repository Structure

```
jio-jcow414-openwrt/
├── .github/
│   └── workflows/
│       └── build-openwrt.yml       # Automated GitHub Actions cloud build workflow
├── files/                          # Rootfs overlay (compiled directly into the image)
│   └── etc/
│       ├── config/
│       │   ├── firewall            # Auto-forwarding for tethered interfaces (usb0, wwan0)
│       │   ├── network             # Pre-configured bridge and DHCP tether interfaces
│       │   └── system              # Pre-configured RGB LED triggers
│       └── hotplug.d/
│           ├── block/
│           │   └── 10-mount        # Automated USB drive partition automount script
│           ├── net/
│           │   └── 40-usb-tether   # Tether network bringup & Blue LED netdev activity
│           └── usb/
│               └── 90-usb-led      # USB insertion hardware pulse
├── tools/
│   └── jiofiber_root_unlocker.py   # Universal 1-click config decryption & root exploit
├── patches/
│   └── 0001-econet-xpon-jcow414.patch  # GPON xPON driver port (econet-xpon, OMCI, JCOW414)
├── build.sh                        # One-command build script for Ubuntu / WSL2
├── Dockerfile                      # Container build definition
├── docker-compose.yml              # Local container orchestration
├── seed.config                     # Minimal seed configuration for defconfig
└── README.md
```

---

## Credits & Acknowledgements

This project builds upon the hard work, reverse engineering, and contributions of the open-source router community:

- **[JFC-Group](https://github.com/JFC-Group)** (`JFC-Group/jiofiber-jcow414-openwrt`): The original community fork and repository that created the initial JCOW414 rootfs overlays, USB tethering hotplug scripts, `jiofiber_root_unlocker.py`, and device packaging.
- **[Sirherobrine23](https://github.com/Sirherobrine23)**: Foundational work porting the EcoNet / Airoha EN7528 target to modern OpenWrt and Linux 6.x.
- **[animasoul](https://github.com/animasoul)** & **[stich81](https://github.com/stich81)**: Groundbreaking reverse engineering of the EcoNet xPON kernel stack, IOCTL dispatcher, and `econet-omcid` daemon.
- **[OpenWrt Project](https://openwrt.org)**: The bedrock open-source embedded Linux operating system and package ecosystem.
- **IndiaBroadband & BroadbandForum Community**: Researchers and enthusiasts who documented Sercomm configuration encryption keys, root unlock vectors, and partition layouts on JioFiber hardware.
- **EcoNet / Airoha / MediaTek**: Original platform BSP, kernel drivers, and GPL source releases.

---

## License & Disclaimer

- This is an independent open-source project and is **not** affiliated with, endorsed by, or sponsored by Reliance Jio Infocomm Ltd. or Sercomm Corporation.
- Licensed under the **GNU General Public License v2.0 (GPL-2.0)**.

