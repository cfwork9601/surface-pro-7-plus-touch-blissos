#!/bin/bash
# Restart the touchpad gesture daemon (/system/etc/touchpad_gestures.sh).
# Usage: ./scripts/restart_gestures.sh [serial]
SERIAL="${1:-192.168.1.107:5555}"

adb -s "$SERIAL" shell '
# Match by exact argv so this adb shell (whose own command line mentions the
# script name) is never killed.
for pid in $(ps -A -o PID,ARGS | awk "\$2==\"sh\" && \$3==\"/system/etc/touchpad_gestures.sh\" {print \$1}"); do
    for child in $(ps -A -o PID,PPID | awk -v p=$pid "\$2==p {print \$1}"); do
        for grandchild in $(ps -A -o PID,PPID | awk -v p=$child "\$2==p {print \$1}"); do kill $grandchild 2>/dev/null; done
        kill $child 2>/dev/null
    done
    kill $pid 2>/dev/null
done
sleep 1
# init only parses rc files at boot; after first install, start manually.
if ! start touchpad_gestures 2>/dev/null || [ "$(getprop init.svc.touchpad_gestures)" != running ]; then
    nohup /system/bin/sh /system/etc/touchpad_gestures.sh >/dev/null 2>&1 &
fi
sleep 2
ps -A -o PID,PPID,ARGS | awk "\$3==\"getevent\" || (\$3==\"sh\" && \$4==\"/system/etc/touchpad_gestures.sh\")"
'
