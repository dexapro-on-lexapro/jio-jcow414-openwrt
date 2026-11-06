# Sercomm JioFiber JCOW414 OpenWrt GPON Port: Autonomous Peer-Agent Handover Guide

**Target Device:** Sercomm JioFiber JCOW414 (and sibling JCO4032)  
**SoC:** EcoNet / Airoha EN7528HU (Dual-core MIPS 1004Kc `mipsel_24kc`, 900 MHz)  
**Kernel:** Linux 6.18.60 (OpenWrt `econet/en7528` snapshot)  
**Build Environment:** Remote Server **Kaveri** (`Host kaveri`, `10.2.1.49` via jump `hamsa-ts`)  
**Flash Safety Status:** Bank 1 (`tclinux`, `mtd2`) Active / Bank 2 (`tclinux_slave`, `mtd5`) Factory Recovery LOCKED.

---

## 1. Absolute Directives & Operational Boundaries

> [!CAUTION]
> ### STRICT BOUNDARY RULES
> 1. **ZERO LOCAL BUILDS:** **NEVER** run `make`, `gcc`, cross-compilation, or Docker compilation on macOS host. ALL builds must run exclusively on **Kaveri** (`10.2.1.49`).
> 2. **NEVER TOUCH BANK 2:** Never write or flash `mtd5` (`tclinux_slave`) or `mtd4` (`kernel_slave`). Bank 2 contains the unbrickable stock factory recovery firmware. Flashing must target `mtd2` (`tclinux`) ONLY.
> 3. **NO SFTP DEPENDENCY:** The target router runs busybox dropbear with no sftp-server subsystem. Always use `scp -O` (legacy SCP protocol) or pipe via SSH.

---

## 2. Infrastructure & Environment Reference

### 2.1. Remote Build Server (Kaveri)
* **SSH Alias:** `ssh kaveri` (Configured in `~/.ssh/config` via ProxyJump `hamsa-ts` to `10.2.1.49`).
* **Container Workspace:** `/tmp/dwaipa-build/workspace`
* **Docker Image:** `dwaipa-openwrt-builder:latest`
* **Build Invocation Pattern:**
  ```bash
  ssh kaveri "docker exec -u 0:0 -w /workspace dwaipa-openwrt-builder-test \
    make package/kernel/econet-xpon/compile V=s -j$(nproc)"
  ```
* **Full Image Build Invocation:**
  ```bash
  ssh kaveri "docker exec -u 0:0 -w /workspace dwaipa-openwrt-builder-test \
    make -j$(nproc)"
  ```
* **Artifact Retrieval:**
  ```bash
  scp -O kaveri:/tmp/dwaipa-build/workspace/bin/targets/econet/en7528/openwrt-*-squashfs-tclinux.trx \
    ~/Documents/Codex/jio-jcow414-openwrt/output/
  ```

### 2.2. Live Target Router (Sercomm JCOW414)
* **Default IP:** `192.168.1.1` (Interface: USB Ethernet adapter `en5`)
* **SSH Access:** `ssh -o StrictHostKeyChecking=no root@192.168.1.1` (Pubkey accepted, root without password)
* **Safe Flashing Sequence:**
  ```bash
  # 1. Transfer image using legacy SCP
  scp -O ~/Documents/Codex/jio-jcow414-openwrt/output/new_tclinux.trx root@192.168.1.1:/tmp/new_tclinux.trx
  
  # 2. Verify SHA256 matches
  ssh root@192.168.1.1 "sha256sum /tmp/new_tclinux.trx"
  
  # 3. Flash Bank 1 ONLY (NEVER tclinux_slave)
  ssh root@192.168.1.1 "mtd write /tmp/new_tclinux.trx tclinux && mtd verify /tmp/new_tclinux.trx tclinux"
  
  # 4. Reboot
  ssh root@192.168.1.1 "reboot"
  ```

---

## 3. Hardware Architecture & Memory Map

### 3.1. Register Space
* **GPON MAC Base:** `0xbfb60000` (CSR block `0x4000`–`0x43C8`)
* **PHY Front-End MMIO:** `0xbfaf0000` (`ANATXREG1` @ `0xbfaf01a0`, `XPON_SETTING` @ `0xbfaf0138`)
* **Transceiver SIF / I2C Bus:** Device address `0x70` (accessed via `e7_rd` / `e7_wr` in kernel driver)

### 3.2. Critical GPON CSR Registers (`0xbfb6XXXX`)
| Address | Name | Stock / Validated Value | Function / Description |
| :--- | :--- | :--- | :--- |
| `0x4000` | `G_ONU_ID` | `0x000000ff` | ONU-ID (`0xff` in O1-O3, assigned in O4/O5) |
| `0x4004` | `G_GBL_CFG` | `0x00000034` | Global configuration (SR block size, FEC) |
| `0x4008` | `G_INT_STATUS` | `0x00100080` (O3) | Interrupt status (Bit 7: `los_gem_del`, Bit 20: `rx_eof_err`) |
| `0x400C` | `G_INT_ENABLE` | `0x77ff0bfd` | Interrupt mask |
| `0x4090` | `G_PLOu_OVERHEAD` | `0x0000000c` | Physical layer overhead time |
| `0x4094` | `G_PLOu_GUARD_BIT`| `0x00000020` | Guard bits (32 bits for Nokia 7360 OLT) |
| `0x4098` | `G_PLOu_PRMBL1_2` | `0x00000000` | Preamble Type 1 and Type 2 bits |
| `0x409C` | `G_PLOu_PRMBL3` | `0x01003779` | Preamble Type 3 (EBL=1, o3o4num=121) |
| `0x40A0` | `G_PLOu_DELM_BIT` | `0x00000018` | Delimiter bits (24 bits = `0xAB6073`) |
| `0x40A4` | `G_PRE_ASSIGNED_DLY` | `0x00000000` | Pre-assigned delay (from OLT message) |
| `0x40AC` | `G_RSP_TIME` | `0x00000577` | Response time ($T_{resp}$ = 1399) |
| `0x40B0` | `G_VENDOR_ID` | `0x53434f4d` | "SCOM" (Sercomm vendor code) |
| `0x40B4` | `G_VS_SN` | `0x994cf513` | Vendor specific SN (`99:4C:F5:13`) |
| `0x40B8` | `G_SN_MSG_CFG` | `0x0a010012` | Serial number message config |
| `0x40BC` | `G_ACTIVATION_ST` | `0x00000003` | GPON state machine status (`3` = O3) |
| `0x4208` | `DBG_DLY` | `[15:8] = 0x1C` | Internal serialization delay fine-tune |
| `0x4310` | `TX_BST_COUNTER` | Dynamic | Total upstream physical bursts transmitted |
| `0x43C4` | `O3_O4_PLOAMU_CTRL`| `0x00000100` | Bit 0: HW/SW mode (0=HW auto SN), Bit 8: Indication |

---

## 4. Authentic Factory Calibration Reference

Extracted from `mtd13` (`reservearea` file offset `0x140477`, magic `0x07050701` at `+0x94`):
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
* **$I_{bias}$ Seed:** `0x610` (1552)
* **$I_{mod}$ Seed:** `0x0CE` (206)
* **Burst Timing Envelope:** `0x504E00AA` ($T_{1C}=0x50, T_{0C}=0x4E$, delay=$0xAA$)
* **DCL MPD Targets:** Word 0 (`0x04A00610`) -> `0x24C/0x27C`; Word 1 (`0x04CE00CE`) -> `0x25C/0x280`.

---

## 5. Live Proc & Sysfs Command Reference

### 5.1. `/proc/econet_xpon_los` Write Handlers
Write single characters to `/proc/econet_xpon_los` to trigger on-demand diagnostics:
* `echo Y > /proc/econet_xpon_los`: Dump active burst envelope (`reg0x08`), $I_{bias}$, $I_{mod}$, and Tx power monitor.
* `echo k > /proc/econet_xpon_los`: Run live PRBS `en7571_tgen_measure(1)` measuring real $T_{0C}/T_{1C}$ turn-on/turn-off times.
* `echo f > /proc/econet_xpon_los`: Measure 3-second delta of `phy_tx_frame_counter()` and `phy_tx_burst_counter()`.
* `echo B > /proc/econet_xpon_los`: Check emission status (`net > 8`) and ramp bias if dark.
* `echo l > /proc/econet_xpon_los`: Trigger manual `en7571_tx_laser_bringup()` (seeds DACs, applies timing latch, engages DCL).
* `echo Z > /proc/econet_xpon_los`: Sweep MMIO SerDes drive swing `ANATXREG1[19:16]` from 0 to 15.
* `echo s > /proc/econet_xpon_los`: Toggle adaptive thermal LUT tracking servo kthread.
* `echo t > /proc/econet_xpon_los`: Toggle TX TDC holdover (`phy_tx_tdc_holdover`).

### 5.2. Key Sysfs Parameters (`/sys/module/econet_xpon/parameters/`)
```bash
# Set dynamic guard bits to match Nokia OLT (32 bits)
echo -1 > /sys/module/econet_xpon/parameters/po_gbits

# Set closed-loop DCL power regulation
echo 2 > /sys/module/econet_xpon/parameters/tx_closeloop

# Set SerDes drive swing (0 = stock default, sweep 0..15)
echo 0 > /sys/module/econet_xpon/parameters/tx_amp

# Set internal serialization delay fine tune (default 28 = 0x1C)
echo 28 > /sys/module/econet_xpon/parameters/po_finetune

# Direct upstream PLOAM byte order (0 = stock no-swab, 1 = swab32)
echo 0 > /sys/module/econet_xpon/parameters/tx_ploam_swab

# Set laser bias and modulation DACs manually
echo 1552 > /sys/module/econet_xpon/parameters/tx_ibias   # 0x610
echo 206  > /sys/module/econet_xpon/parameters/tx_imod    # 0x0CE
echo b > /proc/econet_xpon_los                          # Apply bias
echo i > /proc/econet_xpon_los                          # Apply mod
```

---

## 6. Action Plan to Achieve O4 & O5

### Priority 1: Fine-Tune Response Delay (`po_finetune`)
In stock firmware `xpon_decompiled.c`, `gponDevSetInternalDelayFineTune()` writes to `0x4208[15:8]`.
The burst must arrive within the Nokia OLT's quiet window slot ($1399 \pm \delta$).
Test script pattern:
```bash
for dly in 0 8 16 24 28 32 40 48 56; do
    echo "Testing po_finetune=$dly..."
    ssh root@192.168.1.1 "echo $dly > /sys/module/econet_xpon/parameters/po_finetune"
    sleep 12
    ssh root@192.168.1.1 "dmesg | tail -n 5"
done
```

### Priority 2: Optical Power Threshold Calibration
In live testing, $I_{bias}=0x610$ is near the threshold knee (`net=7`), whereas $0x630$ produces solid lasing (`net=4393`).
Step $I_{bias}$ slightly above threshold while monitoring for OLT acceptance:
```bash
for bias in 1552 1584 1616 1648 1700 1800 1998; do
    echo "Testing tx_ibias=$bias..."
    ssh root@192.168.1.1 "echo $bias > /sys/module/econet_xpon/parameters/tx_ibias; echo b > /proc/econet_xpon_los"
    sleep 12
    ssh root@192.168.1.1 "dmesg | tail -n 5"
done
```

### Priority 3: Monitor for State Progression
A successful handshake will manifest in `dmesg` as:
1. `RNGDBG: Assign_ONU_ID SN-MATCH, curr_state=O3 onu_id=0x...` &rarr; Transition to **O4**.
2. `RNGDBG: o5_eqd_adj_done_int -- EqD ACCEPTED (RANGING SUCCEEDED)` &rarr; Transition to **O5**.
3. `PONLED: O5 -> GREEN(operational)`.
