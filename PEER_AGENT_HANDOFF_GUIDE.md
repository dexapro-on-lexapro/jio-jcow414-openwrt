# JioFiber Sercomm JCOW414 OpenWrt GPON Handoff Guide

> **Target Goal:** Transition GPON MAC from state **O3 (Serial Number acquisition)** to **O5 (Operational)** on OpenWrt 24.10 (Linux 6.18.55).  
> **Safety Rule #1:** **NEVER MODIFY BANK 2 (`tclinux_slave`, mtd5/mtd6/mtd7)**. Bank 2 is the factory-untouched stock recovery partition. Flash ONLY to Bank 1 (`tclinux`, mtd2/mtd3/mtd4).  
> **Current Router Status:** Physically disconnected from power by user. **DO NOT attempt to SSH to 192.168.1.1 until user confirms device is reconnected.**
> **Connection permission:** Ask the user for explicit permission before every remote SSH connection or SCP transfer, including after reconnection.

---

## 1. Quick Reference & Device Profile

| Property | Value |
| :--- | :--- |
| **Model** | Sercomm JioFiber JCOW414 |
| **SoC** | EcoNet / Airoha EN7528HU (Dual-core MIPS 1004Kc, `mipsel_24kc`) |
| **Flash / RAM** | 128 MB NAND Flash / 256 MB DDR3 |
| **Optics** | Integrated EN7571 Optical PMD / BOSA Transceiver |
| **Laser TX_DISABLE Pin** | GPIO 16 (pin 528 on `gpiochip512`). Active LOW to enable laser. |
| **OLT Type** | Nokia / Alcatel-Lucent (ALCL) |
| **GPON Serial Number** | `SCOM994CF513` (Vendor `SCOM`, Vendor-Specific `994CF513`) |
| **PLOAM Password (SLID)** | `00000001` (8 ASCII digits) |
| **WAN MAC** | `8C:A3:99:4C:F5:13` |
| **Data VLAN** | 1015 (802.1Q on `ponwan0`) |
| **Host IP & Port** | `192.168.1.1` (SSH root key accepted, no password) via interface `en5` |
| **Workspace Repo** | `/Users/dwaipayan/Documents/Codex/jio-jcow414-openwrt` |

---

## 2. Backup Archives & Cloud Mirrors

All firmware partitions, bootloader, configurations, and reverse-engineered sources are safely backed up in multiple independent locations.

### A. Pristine Local Copies (Untainted)
Located on local disk at:
```
/Users/dwaipayan/Downloads/JCOW414_FIRMWARE_BACKUP_PRISTINE/
├── jcow414-firmware-backup/ (299 MB)
│   ├── mtd0_bootloader.bin      (256 KB)
│   ├── mtd1_romfile.bin         (256 KB)
│   ├── mtd2_kernel.bin          (4.0 MB)
│   ├── mtd3_rootfs.bin          (35 MB)
│   ├── mtd4_tclinux.bin         (40 MB)
│   ├── mtd5_kernel_slave.bin    (4.0 MB - STOCK RECOVERY)
│   ├── mtd6_rootfs_slave.bin    (34 MB - STOCK RECOVERY)
│   ├── mtd7_tclinux_slave.bin   (40 MB - STOCK RECOVERY)
│   ├── mtd10_ubifs.bin          (26 MB)
│   ├── mtd11_config.bin         (2.0 MB)
│   ├── mtd12_ubifs2.bin         (90 MB)
│   ├── mtd13_reservearea.bin    (2.3 MB - Contains Optical Calibration Table)
│   ├── flash_config_backup.tar.gz
│   └── BACKUP_MANIFEST.txt, SHA256SUMS, MD5SUMS
└── jcow414-r257-dump/ (112 MB)
    ├── xpon_decompiled.c        (Decompiled stock xpon.ko driver)
    ├── omci_decompiled.c        (Decompiled stock OMCI daemon)
    ├── gponmap_decompiled.c
    ├── xponmap_decompiled.c
    ├── RE-FINDINGS.md
    └── stock kernel modules
```

### B. Remote Cloud Uploads (bashupload.app)
- **Essential Backup** (11.6 MB: All partition binaries, decompiled C sources, configs, RE notes):
  - **URL:** `http://bashupload.app/u0e0oy.bin`
  - **Expiration:** 24 hours (multiple downloads enabled)
  - **Download Command:**
    ```bash
    curl -sL http://bashupload.app/u0e0oy.bin -o jcow414_essential_backup.tar.gz
    ```
- **Full Backup Archive** (247 MB: Complete raw images):
  - **URL:** `http://bashupload.app/pf9qgc.bin`
  - **Expiration:** 24 hours (multiple downloads enabled)
  - **Download Command:**
    ```bash
    curl -sL http://bashupload.app/pf9qgc.bin -o jcow414_complete_backup.tar.gz
    ```

---

## 3. The Problem: The GPON O3 Registration Loop

### Symptoms
When the GPON driver (`xpon.ko`) loads with optical fiber connected:
1. Physical link reaches optical lock: `los=0`, `phy_rx_up=1`, `rx_sync=0xa`.
2. OLT broadcasts downstream framing:
   - `Upstream_Overhead` (PLOAM msg `0x01`): `gbits = 0x20` (32 guard bits), `t3_pbits = 0xaa`, `delimiter = 0xAB6073`.
   - `Extended_Burst_Length` (PLOAM msg `0x14`): `raw_o3t3 = 121` bytes, `raw_o5t3 = 55` bytes.
3. State machine transitions from **O1 (Initial)** &rarr; **O2 (Standby)** &rarr; **O3 (Serial Number)**.
4. OLT issues periodic `SN_Request` upstream grants during quiet windows.
5. ONT transmits Serial Number upstream bursts, but the OLT **never responds with `Assign_ONU-ID` (PLOAM msg 0x03)**.
6. After 10 seconds, timer TO1 expires, resetting the ONT back to O2, and the loop repeats:
   ```
   [GPON] State transition: O2 -> O3 (Serial Number)
   ... (10 seconds timeout) ...
   [GPON] State transition: O3 -> O2 (Standby)
   ```

---

## 4. Root Cause Analysis (5 Interlocking Issues Identified)

### Detailed Breakdown

#### 1. Hardcoded Dasan H660GM-A Calibration Table
In `patches/0001-econet-xpon-jcow414.patch` (lines 42740–42930), the driver was populated with calibration parameters from a **Dasan H660GM-A** ONT:
- Overwrites burst timing with `0x444800AA` ($T_{1C}=0x44, T_{0C}=0x48$).
- Overwrites Laser Bias ($I_{bias}$) with `0x7CE` (1998) instead of JCOW414's `0x610` (1552).
- Overwrites Laser Modulation ($I_{mod}$) with `0x157` (343) instead of JCOW414's `0x0CE` (206).
- Overwrites DCL power servo targets with `0x544 / 0x7ce` and `0x523 / 0x157`.

**Impact:** Driving the JCOW414 laser with $I_{mod}=343$ instead of $206$ causes severe overmodulation, eye-pattern distortion, and catastrophic extinction ratio violation. The OLT cannot decode the burst signal.

**The True JCOW414 Calibration Matrix** was discovered in `mtd12` / `mtd13` ("reservearea") at file offset `0x140477` (magic `0x07050701` at `+0x94`):
```c
static const u32 jcow414_flash_cal[100] = {
    0x04a00610, 0x04ce00ce, 0xffffffff, 0x504e00aa, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
    0x001c000d, 0xffffffff, 0xffffffff, 0x00000002, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
    0x00a84ce0, 0xffffffff, 0xffffffff, 0xffffffff, 0x27100fc0, 0x03e80184, 0x00640028, 0xffffffff,
    0xffffffff, 0x00200034, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
    0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0x07050701, 0xffffffff, 0xffffffff,
    /* remaining 60 words: all 0xffffffff or 0x00000000 */
};
```
Key register values:
- Burst Timing register: `0x504E00AA` ($T_{1C}=0x50, T_{0C}=0x4E$, delay=$0xAA$).
- Target Bias: `0x610` (1552).
- Target Mod: `0x0CE` (206).

#### 2. Guard Bits Override (`po_gbits`)
In `patches/0001-econet-xpon-jcow414.patch` (line 50997):
```c
int po_gbits = 24; /* HARDCODED OVERRIDE */
```
The Nokia OLT explicitly requested `32` guard bits (`gbits = 0x20`) in downstream PLOAM message 0x01. Because `po_gbits` was hardcoded to 24, the ONT began transmitting its 24-bit delimiter (`0xAB6073`) 8 bits too early. The OLT's correlator expected the delimiter 8 bits later, missed it, and discarded the entire SN burst.
**Fix:** Set `po_gbits = -1` (to dynamically adopt OLT's requested guard bits) or explicitly `32`.

#### 3. Laser Hardware Enable Pin (GPIO 16)
In `patches/0001-econet-xpon-jcow414.patch` (line 967):
```c
void ledTurnOff(int led) { (void)led; }
void ledTurnOn(int led) { (void)led; }
```
Stock `/userfs/led.conf` specifies:
```
LED_PHY_TX_POWER_DISABLE = 16
```
Because the driver stubs out LED operations, the laser enable pin was unasserted. Laser power reading showed `dark=1030 lit=1030` (completely dark).
Driving GPIO 16 LOW (on `gpiochip512`, pin 528: `echo 528 > /sys/class/gpio/export; echo out > direction; echo 0 > value`) immediately restored laser emission: `dark=1030 lit=1042 => EMITTING`.

#### 4. Serial Number Provisioning
Stock firmware reads the GPON SN from `ctromfile.cfg` in `mtd1`:
```
SerialNumber = "SCOM994CF513"
Password     = "00000001"
wan_mac      = "8C:A3:99:4C:F5:13"
```
The previous provision script erroneously extracted the chassis barcode `RSVOTJHEM028636` from `mtd0`, causing `hex2bin` failure. This was fixed in commit `db46fd8` on `jio-jcow414-openwrt`.

---

## 5. Implementation Checklist for Peer Agent

### Step 1: Update `0001-econet-xpon-jcow414.patch` in `jio-jcow414-openwrt`
1. **Replace Calibration Table:**
   Replace `h660_flash_cal` array with `jcow414_flash_cal`:
   ```c
   static const u32 jcow414_flash_cal[100] = {
       0x04a00610, 0x04ce00ce, 0xffffffff, 0x504e00aa, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
       0x001c000d, 0xffffffff, 0xffffffff, 0x00000002, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
       0x00a84ce0, 0xffffffff, 0xffffffff, 0xffffffff, 0x27100fc0, 0x03e80184, 0x00640028, 0xffffffff,
       0xffffffff, 0x00200034, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
       0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0x07050701, 0xffffffff, 0xffffffff,
   };
   ```
2. **Update Burst Timing Default:**
   In `en7571_gpon_burst_timing()`:
   - Change default `tg` from `0x444800AA` to `0x504E00AA`.
   - Ensure `en7571_T1delay_setting(0)` properly sets the low nibble to `0xA0`.
3. **Fix `po_gbits`:**
   In driver initialization / module param definition:
   - Change `int po_gbits = 24;` &rarr; `int po_gbits = -1;` (let OLT decide) or default to `32`.
4. **Wire Laser Enable to GPIO 16:**
   In `phy_tx_ctl(int enable)`:
   - Request GPIO 16 (or kernel gpio 528).
   - When enabling transmitter: set GPIO 16 to output `0`.
   - When disabling transmitter: set GPIO 16 to output `1`.
5. **Default Driver Module Parameters:**
   Ensure default options load:
   - `erc_openloop=1`
   - `tdc_holdover=1`

### Step 2: Build the Firmware
In `/Users/dwaipayan/Documents/Codex/jio-jcow414-openwrt`:
```bash
./build.sh
```
This targets **EcoNet EN7528 (MIPS)**. Images are built in `openwrt-source/bin/targets/econet/en7528/` and the JCOW414 flashable `*jiofiber_jcow414*tclinux.trx` image is copied to `output/`. Initramfs output requires the corresponding build configuration. Do not use MediaTek Filogic artifacts for this router.

### Step 3: Flash to Live Router (Once Reconnected)
After the user confirms reconnection and explicitly permits the connection, verify the router model, running firmware and `/proc/mtd`. Resolve the partition named exactly `tclinux`, check image size and checksum, and request permission for each subsequent SSH/SCP connection. The following commands are examples, not unattended steps:
```bash
scp output/*jiofiber_jcow414*tclinux.trx root@192.168.1.1:/tmp/
ssh root@192.168.1.1 "mtd write /tmp/jiofiber_jcow414.trx tclinux && reboot"
```
> [!CAUTION]
> ALWAYS verify the target partition is `tclinux` (Bank 1). NEVER write to `tclinux_slave`.

### Step 4: Verification Protocol
Once the router reboots with the fiber cable attached:
1. **Check Laser Emission:**
   ```bash
   cat /proc/econet_xpon_los
   # Verify lit > dark (e.g., dark=1030 lit=1042)
   ```
2. **Inspect GPON State Machine:**
   ```bash
   cat /proc/econet_xpon_status
   ```
   **Expected progression:**
   - `O1: INITIAL` &rarr; `O2: STANDBY` &rarr; `O3: SERIAL NUMBER`
   - Receipt of `Assign_ONU-ID` PLOAM &rarr; `O4: RANGING`
   - Receipt of `Ranging_Time` (EqD adjusted) &rarr; **`O5: OPERATION`**
3. **Check OMCI Daemon:**
   ```bash
   ps | grep omcid
   cat /proc/econet_xpon_gem
   ```
   Verify OMCI daemon negotiates GEM port mappings with the OLT.
4. **Check WAN IP on VLAN 1015:**
   ```bash
   ifstatus pon
   # This overlay names the GPON interface pon; expect DHCP on ponwan0.1015
   ```

---

## 6. Summary of Workspace Git Commits
In repository `/Users/dwaipayan/Documents/Codex/jio-jcow414-openwrt`:
- `db46fd8`: Extracted true GPON serial `SCOM994CF513` from `ctromfile.cfg` in `jio-gpon-provision`.
- `710e646`: Supervised OMCI daemon procd service in `files/etc/init.d/omcid`.
