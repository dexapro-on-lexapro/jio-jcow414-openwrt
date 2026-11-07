# Sercomm JioFiber JCOW414 OpenWrt GPON Activation: Human Reviewer Report

**Document Version:** 3.0 (R2 Update)  
**Date:** 2026-11-07  
**Hardware Target:** Sercomm JCOW414 (EcoNet / Airoha EN7528HU, MIPS 1004Kc, `mipsel_24kc`)  
**Kernel:** Linux 6.18.60 (OpenWrt `main`, target `econet / en7528`)  
**Target OLT:** Nokia 7360 ISAM GPON Linecard (Vendor ID: `ALCL`)  
**Current Operational State:** Downstream locked (`rdy=6`, `rx_sync=0xa`), cycling **O2 (Standby)** $\leftrightarrow$ **O3 (Serial Number / Ranging)** with continuous OLT SN requests  

---

## Executive Summary

This report documents the live optical, register, and protocol reverse engineering performed on the Sercomm JioFiber JCOW414 router running OpenWrt on Bank 1 (`tclinux`, `mtd2`), connected to a live production JioFiber GPON drop on a Nokia 7360 ISAM OLT.

### Key Milestones & Breakthroughs in This Session:

1. **Definitive Whitelist Disproof (The Stock Oracle):**
   * Booted pristine stock firmware R2.52.1 from Bank 2 (`tclinux_slave`, `mtd5`) in read-only mode.
   * Stock reached **O5 (Operational) on the live fiber line within seconds**:
     * ONU ID: `26`, State: `O5`, WAN IP: `10.25.48.15/21` on `bdg1`.
   * **Conclusion:** There is **zero** serial number blocking, no OLT whitelist blacklist, and no line-side fault. The fiber drop, line optics, and hardware are 100% functional. Every barrier to O5 is exclusively inside the OpenWrt driver / analog front-end bring-up.

2. **ROOT CAUSE #1 Identified & Fixed: The Disabled Transmitter (`G_MBI_STOP = 0x101`):**
   * In the OpenWrt port, `G_MBI_STOP` (MAC CSR `0x4160`) was stuck at `0x101` (both TX and RX stopped).
   * It was initialized to stop at driver init and only restarted if the reset scheduler hit the phy-ready branch while downstream remained locked. If downstream lost frame sync during boot reset, the transmitter remained permanently disabled.
   * **Physical impact:** Upstream Serial Number bursts were **never physically leaving the MAC**.
   * **Fix:** Enforced `gponDevMbiStop(XPON_DISABLE)` at reset scheduler completion and forced `0x4160 = 0x00000000` at O3 entry.

3. **ROOT CAUSE #2 Identified & Fixed: Unprogrammed PHY Burst Block (`0x1FAF0400–0x0408`):**
   * A distinct physical-layer burst-shaping CSR block was discovered at physical `0x1FAF0400`.
   * Stock runs:
     * `0x1faf0400` GPON_PREAMBLE: `0xAA000014` (pattern `0xAA`, guard `20`)
     * `0x1faf0404` DELIMITER_GUARD: `0xAAAB6073` (matches Nokia OLT delimiter `AA AB 60` + flag `0x73`)
     * `0x1faf0408` EXTEND_PREAMBLE: `0x00073779` (T3 preamble engine enabled)
   * In OpenWrt, `0x0408` was hardcoded to `0x00000000` (extended preamble engine completely disabled), and `0x0400` had guard bits at `32` instead of `20`.
   * **Fix:** Forced `0x0400 = 0xAA000014`, `0x0404 = 0xAAAB6073`, and `0x0408 = 0x00073779` at O3 entry.

4. **Proof of Progress — Direct OLT Reaction:**
   Immediately upon deploying kernel module `ko8` with these fixes:
   * Serial Number requests from the Nokia OLT changed from 2 requests per cycle followed by silence, to **4+ requests per cycle continuously**.
   * The `ExtBurstLength` handler now actively fires and configures T3 preambles (`o3T3=121`, `o5T3=55`).
   * Transmit monitor power climbed progressively: `4963` $\rightarrow$ `7720` $\rightarrow$ `12985`.
   * The OLT's burst-mode receiver is now physically detecting our energy.

5. **Disassembly of Stock `phy.ko` & `xpon.ko`:**
   * Disassembled stock unstripped kernel modules (`xpon.ko` with 2,011 symbols, `phy.ko` with 445 KB).
   * Confirmed that `gpon_sn_request_threshold_crossed` in stock is a literal no-op (`jr ra; nop`), confirming that the port's power-stepping was unnecessary; `sn_pwr` is now pinned to `0` (stock `DrvPowerLevel=0`).
   * Uncovered that stock `en7571_DCL_start` (@ `0x2bc8c`) is called **unconditionally** during `en7571_init` to start the recovered-clock/data loop (`0x228` byte 1 bit 0), whereas the OpenWrt port had gated it behind `dcl_mode` which was defaulted to disabled.

6. **Evaluation of `AKoo7/openwrt-econet-gpon`:**
   * Cloned and evaluated repository `AKoo7/openwrt-econet-gpon` (branch `h660gm-a-gpon-o5`).
   * Confirmed clean DTS integration for sibling board `jio_jcow407` with identical flash partition layout (`tclinux@0x80000`, `tclinux_slave@0x2880000`, `reservearea@0xddc0000`).
   * Provides a valuable LuCI configuration package (`luci-app-econet-xpon`) and clean build reference.
   * However, Dasan H660GM-A uses a different optical front-end; the Sercomm JCOW414's internal A60928/EN7571 transceiver on EcoNet SIF `0x1FBF8000` requires our dedicated reverse-engineered driver.

---

## Technical Summary Table: Stock vs OpenWrt

| Subsystem | Register / Setting | Stock O5 Reference | OpenWrt (Initial) | OpenWrt (Current ko8) | Status |
|---|---|---|---|---|---|
| **MAC Gate** | `G_MBI_STOP (0x4160)` | `0x00000000` | `0x00000101` (TX & RX stopped) | `0x00000000` | **MATCHED** |
| **PHY Burst Preamble** | `0x1faf0400` | `0xAA000014` (guard 20) | `0xAA000020` (guard 32) | `0xAA000014` | **MATCHED** |
| **PHY Ext Preamble** | `0x1faf0408` | `0x00073779` | `0x00000000` (engine OFF) | `0x00073779` | **MATCHED** |
| **MAC Guard Bits** | `G_PLOu_GUARD_BIT (0x4094)` | `0x14` (20 bits) | `0x20` (32 bits) | `0x14` | **MATCHED** |
| **MAC Debug Delay** | `DBG_DLY (0x4208)` | `0x800E1440` | `0x001C1440` | `0x800E1440` | **MATCHED** |
| **Global Config** | `G_GBL_CFG (0x4004)` | `0x000000D4` (O3) | `0x00000034` | `0x000000D4` | **MATCHED** |
| **SIF Burst Timing** | SIF `0x70` Reg `0x08` | `08 4E 50 A0` | `08 4E 50 A0` | `08 4E 50 A0` | **MATCHED** |
| **Laser Operating Bias** | SIF `0x70` Reg `0x138` | DAC `0x0B6` (182) | DAC `0x610` (uncalibrated) | DAC `0x0B6` | **MATCHED** |
| **Laser Mod Current** | SIF `0x70` Reg `0x148` | DAC `0x271` (625) | DAC `0x0CE` (uncalibrated) | DAC `0x271` | **MATCHED** |
| **SerDes Swing** | `ANATXREG1 (0x1faf01a0)` | `0x00900006` | `0x00990006` | `0x00900006` | **MATCHED** |

---

## Safety & Governance
* **Bank 2 Safety:** Bank 2 (`tclinux_slave`, `mtd5`) has never been written, modified, or reflashed. It remains pristine and serves as our immutable ground-truth oracle.
* **Firmware Switching:** Verified clean toggling between OpenWrt and Stock via `/sbin/en75_chboot` and `/usr/bin/sys bootflag swap`.
