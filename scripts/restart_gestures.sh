#!/bin/bash
# Restart the touchpad gesture daemon (/system/etc/touchpad_gestures.sh).
# Usage: ./scripts/restart_gestures.sh [serial]
SERIAL="${1:-192.168.1.107:5555}"

adb -s "$SERIAL" shell '
# Match by exact argv so this adb shell (whose own command line mentions the
# script name) is never killed.
for pid in $(ps -A -o PID,ARGS | awk "\$2 ~ /(^|\\/)sh\$/ && \$3==\"/system/etc/touchpad_gestures.sh\" {print \$1}"); do
    for child in $(ps -A -o PID,PPID | awk -v p=$pid "\$2==p {print \$1}"); do
        for grandchild in $(ps -A -o PID,PPID | awk -v p=$child "\$2==p {print \$1}"); do kill $grandchild 2>/dev/null; done
        kill $child 2>/dev/null
    done
    kill $pid 2>/dev/null
done
sleep 1
# init only parses rc files at boot; after first install, start manually.
if ! start touchpad_gestures 2>/dev/null || [ "$(getprop init.svc.touchpad_gestures)" != running ]; then
    # Started from adb, the daemon would sit in adbd'"'"'s cgroup (uid_0/pid_<adbd>)
    # and be killed when ADB is turned off. Give it its own cgroup first.
    nohup /system/bin/sh -c "mkdir -p /sys/fs/cgroup/uid_0/touchpad_gestures && echo \$\$ > /sys/fs/cgroup/uid_0/touchpad_gestures/cgroup.procs; exec /system/bin/sh /system/etc/touchpad_gestures.sh" >/dev/null 2>&1 &
fi
sleep 2
ps -A -o PID,PPID,ARGS | awk "\$3==\"getevent\" || (\$3 ~ /(^|\\/)sh\$/ && \$4==\"/system/etc/touchpad_gestures.sh\")"
'
