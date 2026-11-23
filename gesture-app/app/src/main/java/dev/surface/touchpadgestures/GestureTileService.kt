package dev.surface.touchpadgestures

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: turns all touchpad gestures on or off. */
class GestureTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refresh(GestureConfig.load(this))
    }

    override fun onClick() {
        super.onClick()
        val config = GestureConfig.load(this)
        val updated = config.copy(enabled = !config.enabled)
        GestureConfig.save(this, updated)
        refresh(updated)
    }

    private fun refresh(config: GestureConfig) {
        val tile = qsTile ?: return
        tile.state = if (config.enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.subtitle = if (config.enabled) "On" else "Off"
        tile.updateTile()
    }
}
