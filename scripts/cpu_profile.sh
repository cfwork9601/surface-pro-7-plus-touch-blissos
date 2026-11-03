#!/bin/bash
# Switch the tablet's CPU power profile (intel_pstate EPP).
# Not persistent: a reboot returns to the default (balance).
#
#   ./scripts/cpu_profile.sh gaming    # performance governor + EPP performance
#   ./scripts/cpu_profile.sh balance   # powersave governor + balance_performance (boot default)
#   ./scripts/cpu_profile.sh battery   # powersave governor + balance_power
#   ./scripts/cpu_profile.sh           # show current profile

ADB_TARGET="${ADB_TARGET:-192.168.1.107:5555}"
ADB="adb -s $ADB_TARGET"

case "$1" in
    gaming)  GOV=performance; EPP=performance ;;
    balance) GOV=powersave;   EPP=balance_performance ;;
    battery) GOV=powersave;   EPP=balance_power ;;
    "")
        $ADB shell 'echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"; echo "epp:      $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)"'
        exit 0 ;;
    *) echo "Usage: $0 [gaming|balance|battery]"; exit 1 ;;
esac

# With the performance governor, intel_pstate forces EPP to performance,
# so EPP is only written when using powersave.
$ADB shell "for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    echo $GOV > \$c/scaling_governor
    [ $GOV = powersave ] && echo $EPP > \$c/energy_performance_preference
done
echo \"governor: \$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)\"
echo \"epp:      \$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)\""
