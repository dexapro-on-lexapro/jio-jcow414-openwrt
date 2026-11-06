# Sercomm JioFiber JCOW414 OpenWrt GPON: Agent Handover Report

**Target Device:** Sercomm JCOW414 (EcoNet / Airoha EN7528HU, MIPS 24KEc, `mipsel_24kc`)  
**Kernel:** Linux 6.18.60 (OpenWrt `main`, target `realtek` / subtarget `en75xx`)  
**Current State:** Downstream locked (`rdy=6`, `rx_sync=0xa`), cycling **O2** $\leftrightarrow$ **O3** (stalling at Serial Number state)  
**Target State:** **O5 (Operational)**  
**Remote Build Server:** `Host kaveri` (`ssh kaveri`) with container `/tmp/dwaipa-build/workspace`  
**Live Router Access:** `ssh root@192.168.1.1` (Passwordless SSH key, interface `en5`)

---

## 1. Prime Directives & Hard Constraints

> [!CAUTION]
> **NEVER flash, write, or touch Bank 2 (`tclinux_slave`, `mtd5`).**  
> Bank 2 contains the pristine factory Sercomm firmware and is the sole unbrick recovery mechanism. All testing and flashing MUST be confined to Bank 1 (`tclinux`, `mtd2`).

> [!IMPORTANT]
> **Zero Local Compilations:**  
> Never run builds, toolchain builds, or kernel compilations on the macOS workstation. All building must be dispatched via SSH to the remote Linux build container on **Kaveri** (`Host kaveri`).

---

## 2. Breakthrough Findings from This Session

### 2.1. The "Dark Laser" Bias Current Threshold
* **The Problem:** The driver previously initialized $I_{\text{bias}}$ to `0x610` (1552 decimal) from calibration flash slot 0 (`jcow414_get_flash_reg(0)`).
* **The Discovery:** Live optical power readout (`echo B > /proc/econet_xpon_los`) showed:
  ```text
  en7571_tx: dark=1028 lit=1032 net=4 => DARK
  en7571_tx: ramp Ibias=0x610 txpwr=1030 dark=1029 net=1
  en7571_tx: ramp Ibias=0x630 txpwr=3219 dark=1029 net=2190 *** LASING ***
  ```
* **Interpretation:** At `0x610`, the laser diode had NOT reached threshold current. `net = 1` count above dark floor meant the router was transmitting an optical phantom with virtually zero physical photons.
* **The Fix:** Setting $I_{\text{bias}} \ge \text{0x630}$ (1584 decimal) ignites the laser, giving `txpwr = 3219`, `net = 2190` counts above dark floor.

### 2.2. Modulation Current & Optical Extinction Ratio Alignment
* **The Discrepancy:** The OpenWrt driver held modulation current $I_{\text{mod}}$ at `0x0CE` (206 decimal), yielding an MPD current of `0x71` (113).
* **Stock Baseline at O5:** Stock logged `STOCKCMP: BiasCurrent~0x1a9 ModulationCurrent~0x813 MPDCurrent~0x109`.
* **The Alignment:** Elevating $I_{\text{mod}}$ to `0x813` (2067 decimal) via sysfs + `echo i > /proc/econet_xpon_los` elevated the live MPD current to `0xFA` (250), matching stock O5 within 5.6%:
  ```text
  STOCKCMP: BiasCurrent=0x630 ModulationCurrent=0x813 MPDCurrent=0xfa RSSI=0x0 Temp=0x1f1 VCC=0x261 | stock@O5: Bias~0x1a9 Mod~0x813 MPD~0x109
  ```
* `TxMon` reading jumped from 4,963 to 7,720.

### 2.3. SerDes Digital Swing (`ANATXREG1`)
* Live OpenWrt driver had defaulted `ANATXREG1[19:16]` to 9 (`0x00990006`).
* Disassembly of stock `xpon.ko` (`xpon_decompiled.c`) confirmed stock firmware leaves `ANATXREG1[19:16] = 0` (`0x00900006`).
* Configured `tx_amp = 0` via sysfs and applied via `echo l > /proc/econet_xpon_los`.

---

## 3. Hardware Architecture & Register Memory Map

### 3.1. GPON MAC CSR Base (`0xBFB64000`)

| Offset | Register Name | Live Value | Purpose |
|---|---|---|---|
| `0x4008` | `G_INT_STATUS` | `0x00000000` | MAC interrupt status (W1C) |
| `0x400C` | `G_INT_ENABLE` | `0x77ff0bfd` | MAC interrupt mask |
| `0x4094` | `G_PLOu_GUARD_BIT` | `0x00000020` | Guard bits (32 bits) |
| `0x409C` | `G_PLOu_PRMBL_TYPE3` | `0x01003779` | `ebl_en=1`, `o5_num=55`, `o3_o4_num=121` |
| `0x40A0` | `G_PLOu_DELM_BIT` | `0x00000018` | Upstream delimiter length (24 bits = 3 bytes) |
| `0x40AC` | `G_RSP_TIME` | `0x00000577` | ONU response time (1399 clocks = $35\,\mu\text{s}$) |
| `0x40B0` | `G_VENDOR_ID` | `0x53434f4d` | "SCOM" (Sercomm) |
| `0x40B4` | `G_VS_SN` | `0x994cf513` | Serial number `99:4C:F5:13` |
| `0x40B8` | `G_SN_MSG_CFG` | `0x0a0000XX` | `sn_req_thr=10`, `tx_power_mode=0`, random delay |
| `0x40BC` | `G_ACTIVATION_ST` | `0x00000003` | Current activation state (3 = O3) |
| `0x4208` | `DBG_DLY` | `0x001c1c0d` | $\text{fine\_int\_dly} = 28$ (`0x1C`), $\text{phy\_tx\_dly} = 13$ (`0x0D`) |
| `0x4310` | `TX_BST_COUNTER` | Increments +3/cycle | Hardware upstream burst counter |
| `0x4358` | `DS_SPF_CNT` | Steady +8000/s | Downstream superframe counter ($125\,\mu\text{s}$ interval) |

### 3.2. A60928 / EN7571 Optical Transceiver Registers (SIF I2C Dev `0x70`)

| SIF Sub | Register Name | Value | Purpose |
|---|---|---|---|
| `0x08` | `Burst Timing` | `0x084e50a0` | `delay=0xA0`, $T_{1C}=\text{0x50}$, $T_{0C}=\text{0x4E}$, `ERC_en=1` |
| `0x138` | `P0_CS2` ($I_{\text{bias}}$) | `0x0630` | Laser DC bias DAC (lasing threshold crossed) |
| `0x148` | `P1_CS2` ($I_{\text{mod}}$) | `0x0813` | Laser modulation current DAC (stock O5 matched) |
| `0xbfaf0138` | `XPON_SETTING` | `0x0000010f` | Transceiver burst-enable polarity & Tx_SD invert |
| `0xbfaf01a0` | `ANATXREG1` | `0x00900006` | SerDes TX drive swing `[19:16] = 0` (stock value) |

---

## 4. Live Control Handlers (`/proc/econet_xpon_los`)

Writing single characters to `/proc/econet_xpon_los` invokes specific diagnostics:

* `echo B > /proc/econet_xpon_los`: Test laser emission; if dark, ramps $I_{\text{bias}}$ to lasing (`0x630`).
* `echo u > /proc/econet_xpon_los`: Read out live DACs, DCL state, and `STOCKCMP` comparison vs stock O5.
* `echo Y > /proc/econet_xpon_los`: Dump active burst envelope (`reg 0x08`), $I_{\text{bias}}$, $I_{\text{mod}}$, and `TxMon`.
* `echo i > /proc/econet_xpon_los`: Apply `tx_imod` module parameter to SIF register `0x148` live.
* `echo b > /proc/econet_xpon_los`: Apply `tx_ibias` module parameter to SIF register `0x138` live.
* `echo p > /proc/econet_xpon_los`: Apply `tx_xpon` module parameter to `XPON_SETTING` (`0xbfaf0138`) live.
* `echo l > /proc/econet_xpon_los`: Re-run `en7571_tx_laser_bringup()` (applies timing latch, seeds DACs).
* `echo f > /proc/econet_xpon_los`: Read 3-second delta of frame and burst counters.
* `echo 1 > /proc/econet_xpon_usdbg`: Dump all GPON MAC CSR registers (`0x4000` to `0x43C4`) into dmesg.

---

## 5. Immediate Playbook for Next Agent

### Step 1: Verify Hardware Link & Restore Optical Calibration
Connect over SSH and ensure the laser is lasing with stock modulation:
```bash
ssh root@192.168.1.1 "
echo B > /proc/econet_xpon_los
echo 2067 > /sys/module/econet_xpon/parameters/tx_imod
echo i > /proc/econet_xpon_los
echo 0 > /sys/module/econet_xpon/parameters/tx_amp
echo u > /proc/econet_xpon_los
dmesg | tail -n 8
"
```
Verify the output confirms:
* `Ibias=0x630`
* `Imod=0x813`
* `MPDCurrent` between `0xEC` and `0xFA`
* `rdy=6, act_st=O3`

### Step 2: Sweep Serialization Delay Knobs (`po_finetune` & `po_phytxdly`)
Because optical power and modulation amplitude are now verified, the OLT is likely dropping the burst due to timing window arrival (arrival phase relative to the OLT quiet window grant).

Execute a sweep across `po_finetune` (0 to 48 in steps of 4):
```bash
ssh root@192.168.1.1 "
for fine in 0 8 16 20 24 28 32 36 40 48; do
    echo \$fine > /sys/module/econet_xpon/parameters/po_finetune
    echo === Testing po_finetune=\$fine ===
    sleep 12
    dmesg | grep -E 'RNGDBG|Assign_ONU_ID|PONLED: O4|PONLED: O5' | tail -n 5
done
"
```

### Step 3: Hardcode Working Defaults in Kernel Module
In `jio-jcow414-openwrt/patches/0001-econet-xpon-jcow414.patch`:
At line 42878 (`en7571_tx_apc_bringup`):
```c
// Change from:
u16 _im = (u16)(jcow414_get_flash_reg(4) & 0xfff);
en7571_set_imod(_im);
en7571_set_ibias(tgen_dark ? 0 : (u16)(jcow414_get_flash_reg(0) & 0xfff));

// To:
u16 _im = (tx_imod > 0) ? (u16)(tx_imod & 0xfff) : 0x813;
u16 _ib = (tx_ibias > 0) ? (u16)(tx_ibias & 0xfff) : 0x630;
en7571_set_imod(_im);
en7571_set_ibias(tgen_dark ? 0 : _ib);
```
And ensure `tx_amp` defaults to `0`.

### Step 4: Remote Build on Kaveri & Flash Bank 1
```bash
ssh kaveri "
cd /tmp/dwaipa-build/workspace/jio-jcow414-openwrt
# apply patch updates
# make package/kernel/econet-xpon/compile -j$(nproc)
"
```
SCP the built package or sysupgrade image to router Bank 1 (`tclinux`, `mtd2`), verify boot, and inspect dmesg for O5 transition (`PONLED: O5 -> GREEN(operational)`).
