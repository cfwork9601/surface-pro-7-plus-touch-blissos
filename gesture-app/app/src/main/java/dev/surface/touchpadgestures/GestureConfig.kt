package dev.surface.touchpadgestures

import android.content.Context
import java.io.File

/**
 * Settings shared with the root daemon (/system/etc/touchpad_gestures.sh).
 *
 * The app owns `files/gestures.conf` (key=value lines); the daemon reads it on
 * every gesture. The daemon writes `files/status` back so the app can show the
 * last gesture it saw. Action ids must match `run_action` in the daemon.
 */
enum class GestureAction(val id: String, val label: String) {
    NONE("none", "Nothing"),
    HOME("home", "Home"),
    BACK("back", "Back"),
    RECENTS("recents", "Recent apps"),
    LAST_APP("last_app", "Switch to last app"),
    NOTIFICATIONS("notifications", "Notifications"),
    QUICK_SETTINGS("quick_settings", "Quick settings"),
    CLOSE_PANELS("close_panels", "Close panels"),
    SCREENSHOT("screenshot", "Screenshot"),
    PLAY_PAUSE("play_pause", "Play / pause"),
    NEXT_TRACK("next_track", "Next track"),
    PREV_TRACK("prev_track", "Previous track");

    companion object {
        fun fromId(id: String?): GestureAction = entries.firstOrNull { it.id == id } ?: NONE
    }
}

enum class Direction(val id: String, val label: String) {
    UP("up", "Swipe up"),
    DOWN("down", "Swipe down"),
    LEFT("left", "Swipe left"),
    RIGHT("right", "Swipe right"),
}

data class GestureConfig(
    val enabled: Boolean = true,
    val thresholdMm: Int = DEFAULT_THRESHOLD_MM,
    val actions: Map<String, GestureAction> = DEFAULT_ACTIONS,
) {
    fun action(fingers: Int, dir: Direction): GestureAction =
        actions[key(fingers, dir)] ?: GestureAction.NONE

    fun withAction(fingers: Int, dir: Direction, action: GestureAction): GestureConfig =
        copy(actions = actions + (key(fingers, dir) to action))

    companion object {
        const val CONF_FILE = "gestures.conf"
        const val DEFAULT_THRESHOLD_MM = 10
        val FINGERS = listOf(3, 4)

        fun key(fingers: Int, dir: Direction) = "g${fingers}_${dir.id}"

        val DEFAULT_ACTIONS: Map<String, GestureAction> = buildMap {
            for (f in FINGERS) for (d in Direction.entries) put(key(f, d), GestureAction.NONE)
            put(key(3, Direction.UP), GestureAction.RECENTS)
            put(key(4, Direction.UP), GestureAction.HOME)
        }

        fun load(context: Context): GestureConfig {
            val file = File(context.filesDir, CONF_FILE)
            if (!file.exists()) return GestureConfig()
            val values = parseKeyValues(file)
            val actions = DEFAULT_ACTIONS.mapValues { (k, default) ->
                values[k]?.let { GestureAction.fromId(it) } ?: default
            }
            return GestureConfig(
                enabled = values["enabled"] != "0",
                thresholdMm = values["threshold_mm"]?.toIntOrNull() ?: DEFAULT_THRESHOLD_MM,
                actions = actions,
            )
        }

        fun save(context: Context, config: GestureConfig) {
            val text = buildString {
                appendLine("enabled=${if (config.enabled) 1 else 0}")
                appendLine("threshold_mm=${config.thresholdMm}")
                for (f in FINGERS) for (d in Direction.entries) {
                    appendLine("${key(f, d)}=${config.action(f, d).id}")
                }
            }
            val dir = context.filesDir
            val tmp = File(dir, "$CONF_FILE.tmp")
            tmp.writeText(text)
            tmp.setReadable(true, false)
            tmp.renameTo(File(dir, CONF_FILE))
        }
    }
}

/** What the daemon last reported (written by root into our files dir). */
data class DaemonStatus(
    val started: String? = null,
    val device: String? = null,
    val lastTime: String? = null,
    val lastGesture: String? = null,
    val lastAction: String? = null,
) {
    companion object {
        fun load(context: Context): DaemonStatus? {
            val file = File(context.filesDir, "status")
            if (!file.canRead()) return null
            val v = runCatching { parseKeyValues(file) }.getOrNull() ?: return null
            return DaemonStatus(
                started = v["started"]?.ifBlank { null },
                device = v["device"]?.ifBlank { null },
                lastTime = v["last_time"]?.ifBlank { null },
                lastGesture = v["last_gesture"]?.ifBlank { null },
                lastAction = v["last_action"]?.ifBlank { null },
            )
        }
    }
}

private fun parseKeyValues(file: File): Map<String, String> =
    file.readLines()
        .mapNotNull { line ->
            val i = line.indexOf('=')
            if (i <= 0) null else line.substring(0, i).trim() to line.substring(i + 1).trim()
        }
        .toMap()
