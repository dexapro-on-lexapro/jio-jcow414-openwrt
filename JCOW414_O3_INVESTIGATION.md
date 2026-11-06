# JCOW414 O3 investigation — 6 November 2026

The router is offline. The build was cancelled at the user's request. No router network, SSH, SCP, GPIO, register or flash operation was performed during this investigation. Ask permission before every future SSH connection or SSH-based transfer. Do not write Bank 2 (`tclinux_slave`).

The established symptom is failure to progress beyond approximately O3. The current GPIO/calibration/guard-bit edits are an **unverified candidate**, not a diagnosis. No firmware containing those edits has been produced or flashed in this session.

## What the local source establishes

Source boundary: `patches/0001-econet-xpon-jcow414.patch` in this repository. The installed router's module version and runtime parameters have not been established.

- `ploam_recv_upstream_overhead()` accepts broadcast overhead in O2, calls PHY configuration APIs, programs MAC overhead and changes the software/MAC state to O3. It does not check the return values of those PHY calls. Reaching O3 does not establish successful upstream serial-number transmission or reception by the OLT.
- `ploam_recv_assign_onu_id()` checks destination `0xff` and compares all eight serial-number bytes before allowing O3/O2 to advance to O4. This creates distinct possible failure points: no assignment received, assignment lost before parsing, serial mismatch, or a state/reset problem. No live evidence currently distinguishes them.
- Serial provisioning, SN register programming, SN request handling, upstream burst control, downstream FIFO handling, resets and timing remain relevant. GPIO and optical calibration are plausible candidates within that chain; they are not established as the sole cause.
- The ordinary `PON_MSG` logs require `XPON_MAC_CONFIG_DEBUG`, which the checked-in package/build flags do not define. Explicit SN request/transmit and SN-match diagnostics depend on `ploam_verbose`, default `0`. The FIFO logger also suppresses broadcast messages by default, while Assign_ONU-ID is checked as broadcast. Absence of those log lines cannot prove absence of an event.
- The empty-FIFO log-flood idea was considered and rejected for the checked-in flags because its `PON_MSG` call is compiled out. This does not determine the live module's build flags.
- This patch does **not** create `/proc/econet_xpon_status` or `/proc/econet_xpon_gem`.
- `xpon_los_read()` can initialize RX and temporarily change RX polarity registers while probing. Reading `/proc/econet_xpon_los` is not a passive observation and does not produce the claimed TX dark/lit test. Avoid it in the first baseline capture.

## Reference material and its limits

The local `mtd13_reservearea.bin` backup has a 100-word little-endian table at offset `0x140477`. The bytes confirm bias `0x610`, modulation `0x0ce`, timing `0x504e00aa`, and magic `0x07050701`. Matching those bytes establishes the backup data, not that changing them resolves O3.

The saved `jcow414-r257-dump/xpon_decompiled.c` shows the same SN register packing and downstream FIFO byte swap as the port. This is historical decompiler output, not a fresh authoritative decompilation or runtime observation.

REA identified `jcow414-r257-dump/lib/modules/xpon.ko` as a MIPS ELF, SHA-256 `2d40b1d206fe528bea908f5071801defe47fbd8d82b85e4fb6a9430d10642e32`. Fresh native analysis was unavailable: no configured Ghidra/Java provider and no supported installed MIPS disassembler. The session was closed. No toolchain or REA configuration repair was attempted.

## Next discriminating evidence

1. Establish the live board, firmware/module version, runtime SN and diagnostic settings.
2. Observe at least one full activation interval: downstream overhead, SN requests, MAC SN-transmit events, Assign_ONU-ID, serial validation and resets/TO1. An internal MAC transmit indication alone does not prove optical emission or OLT decoding.
3. Use that interval to choose a targeted follow-up. Do not infer optical failure simply from missing Assign_ONU-ID logs. Do not infer a registration fix from manually forced O4/O5.

`tools/jcow414-readonly-diagnostics.sh` is prepared for **one separately permitted SSH connection** after the user confirms reconnection. It reads existing identity, module settings, processes, interrupt counts and kernel logs across 15 seconds. It avoids xPON proc handlers, register/GPIO writes, module reloads, configuration changes and firmware flashing. It has passed shell syntax validation. It may reveal insufficient existing logging; enabling diagnostics would require a separate, explicitly scoped follow-up.

OMCI/GEM and VLAN DHCP checks follow genuine registration/ranging progress. The overlay names the GPON network `pon` on `ponwan0.1015`; `ifstatus wan` does not inspect that interface.
