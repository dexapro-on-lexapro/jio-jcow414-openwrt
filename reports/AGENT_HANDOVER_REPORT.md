# Sercomm JioFiber JCOW414 OpenWrt GPON: Agent Handover Report (R2)

**Date:** 2026-11-07 (end of session 2 — supersedes the R1 handover entirely)  
**Target Device:** Sercomm JCOW414 (EcoNet/Airoha EN7528HU, MIPS 1004Kc, `mipsel_24kc`)  
**Kernel:** Linux 6.18.60 (OpenWrt `main`, target `econet` / subtarget `en7528`, `econet-xpon` driver)  
**Current State:** Downstream locked (`rdy=6`, `rx_sync=0xa`), cycling O2 ↔ O3. **The OLT now hears our bursts** (proven by 4+ continuous SN requests, ExtBurstLength handling, and TxMon rising to 12985) but still never sends `Assign_ONU_ID` (PLOAM msg `0x03` in this driver's enum — never once received).  
**Target State:** O5 (Operational)  
**Remote Build:** Host `kaveri` (`ssh kaveri`), Docker image `jcow414-builder:local`, tree `/tmp/dwaipa-build/workspace/openwrt-source`  
**Live Router:** `ssh root@192.168.1.1` (OpenWrt Bank 1) / `ssh root@192.168.29.1` (Stock Bank 2 with Dropbear). Currently running OpenWrt with kernel module `ko8` deployed.

---

## 0. Prime Directives (STRICT)

1. **NEVER flash, write, or touch Bank 2** (`tclinux_slave`, **mtd5** on this device — always verify by NAME via `cat /proc/mtd`, public repos disagree on numbering). Bank 2 = pristine stock R2.52.1, sole unbrick path. **Booting** Bank 2 is fine and is the project's reference oracle.
2. **Zero local compilations on macOS.** All builds must take place in the Kaveri Docker container `jcow414-builder:local` (tree owned by user `csthps`; patch/build via `docker run -v` mounts).
3. **Bank 1 only** (`tclinux`, `mtd2`) for any flash write. All module deploys this session used **overlay copy-up** of `/lib/modules/6.18.60/econet-xpon.ko` + reboot — zero mtd writes needed.

---

## 0.5 Access & Operational Map

| Task | Procedure / Trap |
|---|---|
| **Which bank is up** | `ping 192.168.1.1` (OpenWrt) vs `ping 192.168.29.1` (Stock). The device flip-flops banks after watchdog crashes — check first, every time. |
| **Bootflag** | ASCII `'0'`=OpenWrt / `'1'`=Factory at **reservearea (mtd12) offset 0x200000**. OpenWrt: `/sbin/en75_chboot factory\|openwrt`. Stock: `/usr/bin/sys bootflag swap` / `boot read`. |
| **Stock root** | Root password does NOT survive stock reboots. Re-arm via `JFC-Group/JFxploit` (uv): `uv run jfxploit run 192.168.29.1 --exploit f01 --action telnet --action iptables --action rootpass -r 'testnet@00'`. |
| **Stock SSH** | Dropbear persists at `/flash2/dropbear` (+ `id_dropbear`). Run `/flash2/dropbear -p 22 -r /flash2/id_dropbear`. Password auth `testnet@00` works over SSH. (Telnet mangles lines >80 chars). |
| **Stock `/dev/mem`** | `/dev/mem` needs `mknod /dev/mem c 1 1` **every stock boot** (devtmpfs). `devmem` takes PHYSICAL addresses (KSEG1 `0xBxxx_xxxx` − `0xA0000000`). |
| **Deploy kmod to OpenWrt** | `scp ko.ko root@192.168.1.1:/tmp/` then **separate ssh**: `cp /tmp/ko.ko /lib/modules/6.18.60/econet-xpon.ko; md5sum both; sync; reboot` (reboot as last command, **no `& exit`** — backgrounded chains get SIGHUP'd and silently abort). |
| **Build inside Docker** | `docker run --rm -v /tmp/dwaipa-build/workspace:/home/builder/workspace -v /tmp/dwaipa-build:/hostbuild --entrypoint bash jcow414-builder:local -c 'python3 /hostbuild/patch.py && cd /home/builder/workspace/openwrt-source && make package/kernel/econet-xpon/clean && make package/kernel/econet-xpon/compile -j1'` — Note: `clean` and `compile` must be separate make invocations. |
| **PLOAM logging** | `echo 1 > /sys/module/econet_xpon/parameters/ploam_verbose` — **mandatory**: with 0, the PLOAM-DS log skips `dest_id=0xff` broadcasts (`gpon_dev.c:80`), and `Assign_ONU_ID` IS a broadcast! |
| **Laser re-arm on OpenWrt** | `echo 182 > /sys/module/econet_xpon/parameters/tx_ibias; echo 625 > /sys/module/econet_xpon/parameters/tx_imod; echo b > /proc/econet_xpon_los; echo i > /proc/econet_xpon_los` (verified live via `Y` handler: `Ibias DAC=0x0B6`, `Imod DAC=0x271`). |

---

## 1. Causal Architecture & Root Causes Solved

### 1.1 Stock Reference Ground Truth (The Oracle)
* Bank 2 (stock R2.52.1) achieves **O5 live on this fiber**:
  * ONU ID: `26`, Serial Number: `SCOM994cf513`, PLOAM Password: `00000001`, WAN IP: `10.25.48.15/21` on `bdg1`, OLT Vendor ID: `ALCL` (Nokia 7360 ISAM).
  * Fiber optics, whitelist, and serial registration are 100% operational.

### 1.2 ROOT CAUSE #1: `G_MBI_STOP = 0x101` (Transmitter Hard-Stopped)
* **Mechanism:** `G_MBI_STOP` (MAC CSR `0x4160`): bit 0 = `mbi_rx_stop`, bit 8 = `mbi_tx_stop`. The OpenWrt driver was leaving this register at `0x101` (both TX and RX stopped).
* **Cause:** Set at `gpon_init.c:195`, only restarted inside `gpon_enable()` on the phy-ready path of the reset scheduler (`handle_xpon_daemon_job_gpon_dev_reset`). If downstream lost sync during reset, it took the O1 branch and MBI stayed dead forever.
* **Fix (ko8):** The reset scheduler now unconditionally executes `gponDevMbiStop(XPON_DISABLE)`, and `0x4160 = 0x00000000` is enforced at O3 entry in `gpon_act.c`.
* **Verification:** `0x4160 = 0x00000000` verified live at every O3 entry.

### 1.3 ROOT CAUSE #2: Unprogrammed PHY Burst Block (`0x1FAF0400–0x0408`)
* **Mechanism:** A distinct physical-layer burst-framing block shapes upstream bursts:
  * `0x1faf0400` GPON_PREAMBLE: `0xAA000014` (pattern `0xAA`, guard `20`)
  * `0x1faf0404` DELIMITER_GUARD: `0xAAAB6073` (Nokia OLT delimiter `AA AB 60` + flag `0x73`)
  * `0x1faf0408` EXTEND_PREAMBLE: `0x00073779` (T3 preamble engine)
* **Port Bug:** OpenWrt had `0x0408 = 0x00000000` (extended burst engine completely disabled), causing SN bursts to transmit without extended preambles.
* **Fix (ko8):** Enforced `0x0400 = 0xAA000014`, `0x0404 = 0xAAAB6073`, `0x0408 = 0x00073779` at O3 entry.

### 1.4 Additional Critical Corrections in ko8
* `G_GBL_CFG (0x4004)`: Stock O3 = `0x000000D4` (`sr_blk_size=212`). Port had `0x34`. Forced `0xD4`. (Note: bit 16 `0x100` is for O5 only; do not set in O3).
* `0x1faf0264 (SW_RDI)`: Port had bit 4 set. Stock is `0x27101100`. Forced.
* `sn_pwr` pinned to `0` (stock `DrvPowerLevel=0`). Port default `-1` stepped power levels 0→1→2 through uninitialized P1/P2 DACs.

---

## 2. Stock Binary Reverse Engineering & Optical Disassembly

Stock firmware binaries extracted from Bank 2 rootfs (`bank2-extract/rootfs/lib/modules/`):
* `xpon.ko` (458 KB, unstripped, 2,011 symbols): GPON MAC and state machine.
* `phy.ko` (445 KB, unstripped): Optical transceiver controller and A60928/EN7571 driver.
* `sif.ko` (42 KB, unstripped): Hardware SIF master controller driver (`0xBFBF8000`).

### Key Findings from Disassembly:
1. `gpon_sn_request_threshold_crossed` (@ `0x114b0` in `xpon.ko`):
   * Literal no-op (`jr ra; nop`). The port's power-mode stepping was invented and has been neutralized.
2. `en7571_DCL_start` (@ `0x2bc8c` in `phy.ko`):
   * Unconditionally called at step 27 of `en7571_init` (@ `0x2ab90`).
   * Reads reg `0x228`, sets bit 0 of byte 1 (`0x229[0]=1`), and writes back 4 bytes to `0x228`.
   * In `phy_init.c:1810`, the OpenWrt port had wrapped this call in `if (dcl_mode)` with `dcl_mode` defaulted to 0. Stock **always** starts DCL!
3. `en7571_T1delay_setting` (@ `0x3c5e8` in `phy.ko`):
   * Sets low nibble of SIF reg `0x08` to `0xA0` (clearing `0xAA` to `0xA0`), exactly matching the live stock read `08 4E 50 A0`.

---

## 3. Register Verification Table (O3 Active State)

| Register | Address / Bus | Stock Live Value | OpenWrt ko8 | Verification |
|---|---|---|---|---|
| `G_GBL_CFG` | `0xBFB64004` | `0x000000D4` | `0x000000D4` | Verified |
| `G_PLOu_GUARD_BIT` | `0xBFB64094` | `0x00000014` (20 bits) | `0x00000014` | Verified |
| `G_PLOu_T3` | `0xBFB6409C` | `0x01003779` | `0x01003779` | Verified |
| `G_MBI_STOP` | `0xBFB64160` | `0x00000000` | `0x00000000` | Verified |
| `DBG_DLY` | `0xBFB64208` | `0x800E1440` | `0x800E1440` | Verified |
| `GPON_PREAMBLE` | `0xBFAF0400` | `0xAA000014` | `0xAA000014` | Verified |
| `DELIMITER_GUARD`| `0xBFAF0404` | `0xAAAB6073` | `0xAAAB6073` | Verified |
| `EXTEND_PREAMBLE`| `0xBFAF0408` | `0x00073779` | `0x00073779` | Verified |
| SIF Reg `0x08` | SIF `0x70` Reg 8 | `08 4E 50 A0` | `08 4E 50 A0` | Verified |
| SIF Reg `0x138` | SIF `0x70` Reg 0x138 | DAC `0x0B6` (182) | DAC `0x0B6` | Verified |
| SIF Reg `0x148` | SIF `0x70` Reg 0x148 | DAC `0x271` (625) | DAC `0x271` | Verified |
| `ANATXREG1` | `0xBFAF01A0` | `0x00900006` | `0x00900006` | Verified |

---

## 4. Evaluation of `AKoo7/openwrt-econet-gpon`

* **Repository:** `https://github.com/AKoo7/openwrt-econet-gpon` (branch `h660gm-a-gpon-o5`)
* **Relevance:**
  1. Contains device tree `target/linux/econet/dts/en7528_jio_jcow407.dts` which matches JCOW414 flash partition layout (`bootloader@0`, `tclinux@0x80000 (0x2800000)`, `tclinux_slave@0x2880000`, `reservearea@0xddc0000`).
  2. Demonstrates successful upstream OpenWrt PR #24577 integration for Dasan H660GM-A reaching O5 on Airtel GPON.
  3. Includes `luci-app-econet-xpon` for Web UI configuration of GPON parameters.
* **Caveat:** Dasan H660GM-A uses an external SFP or different BOSA front-end (MT7570). The Sercomm JCOW414's internal A60928/EN7571 optical front-end is distinct and relies on the SIF protocol reverse-engineered from stock Sercomm `phy.ko`/`sif.ko`.

---

## 5. Immediate Next Playbook

1. **Step 1: Enable DCL Servo Start (`en7571_DCL_start`):**
   * Update `en7571_reg_init_full()` in `phy_init.c` to start DCL unconditionally (or boot with `dcl_mode=1`).
2. **Step 2: Optical Init Sequence Verification:**
   * Verify whether `en7571_TxSD_level_set` or `en7571_load_tx_cal_data` needs to run after laser bring-up.
3. **Step 3: Test on Live Router:**
   * Reconnect Ethernet cable (`en5`).
   * Compile on Kaveri, deploy to router, monitor with `echo 1 > /sys/module/econet_xpon/parameters/ploam_verbose`.
   * Await `Assign_ONU_ID` $\rightarrow$ `o5_eqd_adj_done_int` $\rightarrow$ **`PONLED: O5 -> GREEN(operational)`**.
