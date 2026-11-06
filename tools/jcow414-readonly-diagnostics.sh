#!/bin/sh
# Run on the JCOW414 only after permission for that SSH connection.
# Collect existing state; avoid xPON proc handlers that perform register writes.

printf '\nJCOW414 diagnostic capture\n'
date -u
uname -a
for path in /tmp/sysinfo/model /tmp/sysinfo/board_name /etc/openwrt_release; do
    if [ -r "$path" ]; then
        printf '\n%s\n' "$path"
        cat "$path"
    fi
done

printf '\nConfigured GPON serial\n'
uci -q get econet-xpon.identity.gpon_sn

printf '\nLoaded modules\n'
cat /proc/modules

printf '\nDriver settings\n'
for module in econet_xpon econet-xpon xpon; do
    for param in gpon_sn sn_vs ploam_verbose tx_laser_off erc_openloop tdc_holdover po_gbits \
        po_rsp po_finetune po_phytxdly sn_pwr tx_ibias tx_imod fast_ploam_ms \
        mac_activate auto_lock tgen_dark tgen_settle tx_xpon; do
        path="/sys/module/$module/parameters/$param"
        if [ -r "$path" ]; then
            printf '%s.%s=' "$module" "$param"
            cat "$path"
        fi
    done
done

printf '\nProcesses\n'
ps
printf '\nInterrupt snapshot before observation\n'
cat /proc/interrupts
printf '\nKernel log before observation\n'
dmesg

sleep 15

printf '\nObservation end\n'
date -u
printf '\nInterrupt snapshot after observation\n'
cat /proc/interrupts
printf '\nKernel log after observation\n'
dmesg
