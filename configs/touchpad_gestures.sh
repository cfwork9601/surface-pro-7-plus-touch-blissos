#!/system/bin/sh
# Multi-finger touchpad gestures for the Surface Type Cover (Android 13 has none).
#
# Defaults: 3 fingers swipe up -> Recents, 4 fingers swipe up -> Home.
# Configurable with the "Touchpad Gestures" app (gesture-app/ in the repo),
# which writes $CONF below. The daemon works without the app (defaults).
#
# Pipeline: getevent (passive, no grab, so Android keeps normal pointer and
# scroll behaviour) -> awk (detects a 3/4-finger swipe, prints "<fingers> <dx>
# <dy>" when all fingers lift) -> shell loop (reads config, picks the action).
# Actions go through `cmd input` / `cmd statusbar` (native binder calls, NOT
# app_process, so no /proc/cpuinfo bind-mount leak). Started by
# touchpad_gestures.rc.

PATH=/system/bin:/system/xbin:/vendor/bin
TOUCHPAD_NAME="Microsoft Surface Type Cover Touchpad"
UNITS_PER_MM=20   # touchpad resolution reported by the kernel
# Touchpad ABS_X / ABS_Y max (about 98 x 50 mm). Up/down swipes have about half
# the room of left/right ones, so the vertical threshold is scaled by PAD_H/PAD_W.
PAD_W=1956
PAD_H=997

APP_DIR=/data/user/0/dev.surface.touchpadgestures/files
CONF=$APP_DIR/gestures.conf
STATUS=$APP_DIR/status

STARTED=$(date '+%Y-%m-%d %H:%M:%S')

find_touchpad() {
    for sysnode in /sys/class/input/event*; do
        [ -r "$sysnode/device/name" ] || continue
        read -r devname < "$sysnode/device/name"
        if [ "$devname" = "$TOUCHPAD_NAME" ]; then
            echo "/dev/input/${sysnode##*/}"
            return
        fi
    done
}

# Read the app's config with shell builtins only (no forks, no eval: the file
# is written by an unprivileged app, so only whitelisted keys/values are used).
load_config() {
    enabled=1; threshold_mm=10
    g3_up=recents; g3_down=none; g3_left=none; g3_right=none
    g4_up=home;    g4_down=none; g4_left=none; g4_right=none
    [ -r "$CONF" ] || return
    while IFS='=' read -r k v; do
        case "$v" in *[!a-z0-9_]*|"") continue ;; esac
        case "$k" in
            enabled)      enabled=$v ;;
            threshold_mm) case "$v" in *[!0-9]*) ;; *) threshold_mm=$v ;; esac ;;
            g3_up) g3_up=$v ;; g3_down) g3_down=$v ;; g3_left) g3_left=$v ;; g3_right) g3_right=$v ;;
            g4_up) g4_up=$v ;; g4_down) g4_down=$v ;; g4_left) g4_left=$v ;; g4_right) g4_right=$v ;;
        esac
    done < "$CONF"
}

run_action() {
    case "$1" in
        home)           cmd input keyevent KEYCODE_HOME ;;
        back)           cmd input keyevent KEYCODE_BACK ;;
        recents)        cmd input keyevent KEYCODE_APP_SWITCH ;;
        # Quick switch (like a swipe along the bottom bar): Launcher3/Quickstep
        # treats a 2nd Recents press while Overview opens as "launch the
        # previous task", with its animation. Works for split-screen pairs and
        # web apps, which `am start` cannot reopen.
        last_app)       cmd input keyevent KEYCODE_APP_SWITCH KEYCODE_APP_SWITCH ;;
        notifications)  cmd statusbar expand-notifications ;;
        quick_settings) cmd statusbar expand-settings ;;
        close_panels)   cmd statusbar collapse ;;
        screenshot)     cmd input keyevent KEYCODE_SYSRQ ;;
        play_pause)     cmd input keyevent KEYCODE_MEDIA_PLAY_PAUSE ;;
        next_track)     cmd input keyevent KEYCODE_MEDIA_NEXT ;;
        prev_track)     cmd input keyevent KEYCODE_MEDIA_PREVIOUS ;;
        *)              return 1 ;;
    esac >/dev/null 2>&1
}

# Status file the app shows ("last gesture"). Only written if the app exists.
write_status() {
    [ -d "$APP_DIR" ] || return
    {
        echo "started=$STARTED"
        echo "device=$dev"
        echo "last_time=$(date '+%H:%M:%S')"
        echo "last_gesture=$1"
        echo "last_action=$2"
    } > "$STATUS.tmp" && chmod 644 "$STATUS.tmp" && mv -f "$STATUS.tmp" "$STATUS"
}

# $1 = fingers, $2 = avg dx, $3 = avg dy (device units, per finger)
handle_gesture() {
    load_config
    [ "$enabled" = 1 ] || return
    fingers=$1; dx=$2; dy=$3
    [ "$fingers" -gt 4 ] && fingers=4
    ax=${dx#-}; ay=${dy#-}
    # Normalise vertical travel to the pad's width, so one threshold works in
    # both directions: e.g. 10 mm sideways ~ 5 mm up/down.
    ny=$((ay * PAD_W / PAD_H))
    th=$((threshold_mm * UNITS_PER_MM))
    dir=""
    if [ "$ny" -ge "$th" ] && [ $((ny * 2)) -gt $((ax * 3)) ]; then
        if [ "$dy" -lt 0 ]; then dir=up; else dir=down; fi
    elif [ "$ax" -ge "$th" ] && [ $((ax * 2)) -gt $((ny * 3)) ]; then
        if [ "$dx" -lt 0 ]; then dir=left; else dir=right; fi
    fi
    if [ -z "$dir" ]; then
        # Too short or too diagonal: log it so the threshold can be tuned.
        log -t touchpad_gestures "$fingers fingers ignored: dx=$((dx / UNITS_PER_MM))mm dy=$((dy / UNITS_PER_MM))mm (need ${threshold_mm}mm sideways or $((threshold_mm * PAD_H / PAD_W))mm up/down)"
        write_status "$fingers fingers: too short (dx $((dx / UNITS_PER_MM)) mm, dy $((dy / UNITS_PER_MM)) mm)" none
        return
    fi
    # Rotation-aware: the touchpad turns with the tablet, so map pad
    # directions to screen directions ("up" = towards the top of the screen).
    # Rotation is read once per gesture (~25 ms), never while idle.
    paddir=$dir
    rot=$(dumpsys window displays 2>/dev/null | grep -m1 -o " mRotation=[0-3]")
    case "${rot##*=}$dir" in
        1up) dir=left ;;  1down) dir=right ;; 1left) dir=down ;;  1right) dir=up ;;
        2up) dir=down ;;  2down) dir=up ;;    2left) dir=right ;; 2right) dir=left ;;
        3up) dir=right ;; 3down) dir=left ;;  3left) dir=up ;;    3right) dir=down ;;
    esac
    case "$fingers$dir" in
        3up) a=$g3_up ;; 3down) a=$g3_down ;; 3left) a=$g3_left ;; 3right) a=$g3_right ;;
        4up) a=$g4_up ;; 4down) a=$g4_down ;; 4left) a=$g4_left ;; 4right) a=$g4_right ;;
        *) return ;;
    esac
    if [ "$a" != none ] && run_action "$a"; then :; else a=none; fi
    log -t touchpad_gestures "$fingers fingers $dir (pad: $paddir, rotation ${rot##*=}) -> $a"
    write_status "$fingers fingers $dir" "$a"
}

# --- Device watchdog --------------------------------------------------------
# When the Type Cover re-enumerates (sleep/resume, fold, reattach) its node is
# deleted and recreated. getevent does NOT exit on a deleted node: it spins at
# 100% of a CPU core reading nothing. So watch /dev/input (event-driven) and
# kill getevent whenever our node is deleted or a new touchpad node appears;
# the main loop then reopens the current node.
# NOTE: toybox inotifyd ignores the first mask letter, so ":nnd" = create+delete.
RUN=/dev/touchpad_gestures
mkdir -p "$RUN"
GETEVENT_PID=$RUN/getevent.pid
CUR_NODE=$RUN/node

kill_reader() {
    [ -r "$GETEVENT_PID" ] || return
    read -r pid < "$GETEVENT_PID"
    rm -f "$GETEVENT_PID"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
}

(
    while true; do
        inotifyd - /dev/input:nnd | while read -r ev _dir node; do
            case "$node" in event*) ;; *) continue ;; esac
            cur=""
            [ -r "$CUR_NODE" ] && read -r cur < "$CUR_NODE"
            if [ "$ev" = d ] && [ "$node" = "$cur" ]; then
                kill_reader
            elif [ "$ev" = n ] && [ -r "/sys/class/input/$node/device/name" ]; then
                read -r devname < "/sys/class/input/$node/device/name"
                [ "$devname" = "$TOUCHPAD_NAME" ] && kill_reader
            fi
        done
        sleep 5   # inotifyd exited unexpectedly; restart it
    done
) &

dev=""
write_status "" ""
while true; do
    dev=$(find_touchpad)
    if [ -z "$dev" ] || [ ! -e "$dev" ]; then
        rm -f "$CUR_NODE"
        sleep 3   # Type Cover detached; check again shortly
        continue
    fi
    echo "${dev##*/}" > "$CUR_NODE"
    log -t touchpad_gestures "watching $dev"
    write_status "" ""

    # getevent with a single device prints: "<type> <code> <value>" in hex.
    # Run it via a tiny sh that records its PID, then execs (same PID) so the
    # watchdog can kill exactly this reader.
    sh -c 'echo $$ > "$1"; exec getevent "$2" 2>/dev/null' _ "$GETEVENT_PID" "$dev" | awk '
    function hex(s,   i, n) {
        n = 0
        s = tolower(s)
        for (i = 1; i <= length(s); i++)
            n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
        return n
    }
    function reset(   k) {
        fingers = 0; maxf = 0; sdx = 0; sdy = 0
        for (k in hx) delete hx[k]
        for (k in hy) delete hy[k]
    }
    BEGIN { slot = 0; reset() }
    NF == 3 {
        type = $1; code = $2; val = $3
        if (type == "0001") {                       # EV_KEY
            if (code == "014a" && val == "00000000") {      # BTN_TOUCH up: all fingers lifted
                if (maxf >= 3) {
                    printf "%d %d %d\n", maxf, int(sdx / maxf), int(sdy / maxf)
                    fflush()
                }
                reset()
            } else if (val == "00000001") {
                if      (code == "0145") fingers = 1   # BTN_TOOL_FINGER
                else if (code == "014d") fingers = 2   # BTN_TOOL_DOUBLETAP
                else if (code == "014e") fingers = 3   # BTN_TOOL_TRIPLETAP
                else if (code == "014f") fingers = 4   # BTN_TOOL_QUADTAP
                else if (code == "0148") fingers = 5   # BTN_TOOL_QUINTTAP
                if (fingers > maxf) maxf = fingers
            }
        } else if (type == "0003") {                # EV_ABS
            if (code == "002f") {                   # ABS_MT_SLOT
                slot = hex(val)
            } else if (code == "0039") {            # ABS_MT_TRACKING_ID (new or lifted contact)
                delete hx[slot]; delete hy[slot]
            } else if (code == "0035") {            # ABS_MT_POSITION_X
                v = hex(val)
                if (fingers >= 3 && (slot in hx)) sdx += v - hx[slot]
                hx[slot] = v
            } else if (code == "0036") {            # ABS_MT_POSITION_Y
                v = hex(val)
                if (fingers >= 3 && (slot in hy)) sdy += v - hy[slot]
                hy[slot] = v
            }
        }
    }' | while read -r n dx dy; do
        handle_gesture "$n" "$dx" "$dy"
    done

    # Reader was killed by the watchdog (node deleted/recreated) or exited.
    sleep 1
done
