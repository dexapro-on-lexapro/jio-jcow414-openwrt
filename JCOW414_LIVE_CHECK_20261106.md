# JCOW414 live check — 6 November 2026

The user confirmed that the router and PON fiber are connected and authorized SSH only to the router through `en5`. The user initially described recovery as unavailable, then explicitly answered that a tested recovery path is available. The method has not been specified. Do not infer that this is Bank 2 recovery from older handoff claims. Do not write `tclinux_slave`.

## Verified device and path

- Host route to `192.168.1.1` uses `en5`; the observed local address is `192.168.1.155`.
- SSH identified model `JioFiber JCOW414`, board `jiofiber,jcow414`, target `econet/en7528`, architecture `mipsel_24kc`, kernel `6.18.55`.
- The live partition map names `mtd2` as `tclinux`, size `0x02800000` (40 MiB), erase size `0x20000`. `mtd5` is `tclinux_slave`. Resolve names from the live map; historical partition numbers differ.

## Observed activation and calibration

- Configured and loaded GPON serial: `SCOM994CF513`; `sn_vs=0`.
- Runtime defaults are still `erc_openloop=0`, `tdc_holdover=0`, `po_gbits=24`.
- Existing boot logs report actual programmed bias `0x7CE`, modulation `0x157`, delay `0xAA`, T0C `0x48`, T1C `0x44`.
- A read of 400 bytes from the live `reservearea` partition (`/dev/mtd12ro`, offset `0x140477`) reports bias `0x610`, modulation `0x0CE`, timing `0x504E00AA`, and GPON magic `0x07050701`.
- All 100 live calibration words match `jcow414_flash_cal` in the current candidate patch. Calibration SHA-256: `8a46ae17ab7532bbdaba4e81203262af47e3b0ab28972f067254bc0d54ea88ed`.
- Kernel pinctrl reports GPIO 16 unclaimed and configured as an input. This establishes its current configuration; it does not independently establish its electrical role or optical output.
- The device repeatedly enters O3 and times out to O2. A 24-second `ploam_verbose=1` capture includes three SN requests/transmit indications at uptime 345.65–346.25 seconds, TO1 expiry at 355.75 seconds, and another three at 356.65–357.25 seconds. No Assign_ONU-ID (`msg_id=03`) or O4/O5 appears during that interval. These MAC indications do not establish optical emission or OLT decoding. The original value `0` was restored and checked afterward.
- `omcid` is running with the expected serial. GPON receive counters and GEM mappings are empty; the OMCC ID is `65535`. `ifstatus pon` shows DHCP pending without an address.

The calibration mismatch and unconfigured GPIO are supported candidate causes. They are not a proven diagnosis. No manual state forcing, laser test pattern, GPIO write, module replacement/reload, flash write, or reboot was performed during these captures.

## Build and verification boundaries

The candidate already includes GPIO output control (enable=0, disable=1), device-tree GPIO resolution, factory calibration, OLT-supplied guard bits, and `erc_openloop=1 tdc_holdover=1` defaults. The build is running in Docker against the saved Linux source/build volume. Build log: `output/build-live-20261106.log`.

The correct firmware target is `econet/en7528`, not MediaTek Filogic. Older files in `output/` date from 1 November and do not contain this candidate. Only newly completed, verified artifacts are eligible for use.

The current 40-MiB Bank 1 contents were read into `output/router-bank1-before-20261106.bin`. Its local SHA-256 exactly matches a second hash read on the router: `8fbaa06a574930031fad03f2fb24090a256e9c471bea50add722215210dfa6b5`. An `/etc` archive is saved as `output/router-etc-before-20261106.tar.gz`; these backups are owner-readable only. This preserves data but does not establish recoverability. The current Bank 1 header is `HDR2` and UBI starts at offset 4 MiB, consistent with the candidate target's container layout.

The checked-in driver does not implement `/proc/econet_xpon_status` or `/proc/econet_xpon_gem`. Reading `/proc/econet_xpon_los` can perform hardware initialization/polarity changes and does not provide a dark/lit emission test. The configured GPON UCI interface is `pon` on `ponwan0.1015`.

Raw captures are in `output/router-baseline-20261106.log`, `output/router-links-gpio-20261106.log`, `output/router-activation-20261106.log`, and `output/router-activation-full-20261106.log`. The user subsequently confirmed a tested recovery path is available. A successful build alone does not prove safe boot or resolve O3; validate the new artifacts and resolve the live partition by its exact name before deployment.
