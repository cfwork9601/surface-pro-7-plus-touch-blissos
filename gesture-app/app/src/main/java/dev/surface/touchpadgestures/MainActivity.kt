package dev.surface.touchpadgestures

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/** Touchpad height / width (ABS ranges 997 / 1956); must match PAD_H/PAD_W in the daemon. */
private const val PAD_HEIGHT_RATIO = 997f / 1956f

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val context = LocalContext.current
            val colors = if (isSystemInDarkTheme()) dynamicDarkColorScheme(context)
            else dynamicLightColorScheme(context)
            MaterialTheme(colorScheme = colors) { GestureScreen() }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GestureScreen() {
    val context = LocalContext.current
    var config by remember { mutableStateOf(GestureConfig.load(context)) }
    var status by remember { mutableStateOf(DaemonStatus.load(context)) }

    fun update(new: GestureConfig) {
        config = new
        GestureConfig.save(context, new)
    }

    // While the screen is visible: poll the daemon's status file and pick up
    // changes made from the Quick Settings tile.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            config = GestureConfig.load(context)
            while (true) {
                status = DaemonStatus.load(context)
                delay(1000)
            }
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Touchpad Gestures") }) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = Modifier.widthIn(max = 1000.dp).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                EnableCard(config.enabled) { update(config.copy(enabled = it)) }

                val wide = LocalConfiguration.current.screenWidthDp >= 720
                if (wide) {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        for (f in GestureConfig.FINGERS) {
                            FingerCard(f, config, config.enabled, Modifier.weight(1f)) { update(it) }
                        }
                    }
                } else {
                    for (f in GestureConfig.FINGERS) {
                        FingerCard(f, config, config.enabled, Modifier.fillMaxWidth()) { update(it) }
                    }
                }

                SensitivityCard(config, onChange = { config = it }, onDone = { update(it) })
                StatusCard(status)
                TextButton(
                    onClick = { update(GestureConfig(enabled = config.enabled)) },
                    modifier = Modifier.align(Alignment.End),
                ) { Text("Reset to defaults") }
                Spacer(Modifier.padding(8.dp))
            }
        }
    }
}

@Composable
private fun SectionCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
    }
}

@Composable
private fun EnableCard(enabled: Boolean, onChange: (Boolean) -> Unit) {
    SectionCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Touchpad gestures", style = MaterialTheme.typography.titleMedium)
                Text(
                    if (enabled) "Multi-finger swipes on the Type Cover touchpad are active."
                    else "Gestures are off. Normal pointer and scrolling still work.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(16.dp))
            Switch(checked = enabled, onCheckedChange = onChange)
        }
    }
}

@Composable
private fun FingerCard(
    fingers: Int,
    config: GestureConfig,
    enabled: Boolean,
    modifier: Modifier,
    onChange: (GestureConfig) -> Unit,
) {
    SectionCard(modifier) {
        Text("$fingers fingers", style = MaterialTheme.typography.titleMedium)
        for (dir in Direction.entries) {
            ActionPicker(
                label = dir.label,
                selected = config.action(fingers, dir),
                enabled = enabled,
            ) { onChange(config.withAction(fingers, dir, it)) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActionPicker(
    label: String,
    selected: GestureAction,
    enabled: Boolean,
    onSelect: (GestureAction) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded && enabled,
        onExpandedChange = { if (enabled) expanded = it },
    ) {
        OutlinedTextField(
            value = selected.label,
            onValueChange = {},
            readOnly = true,
            enabled = enabled,
            singleLine = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor(MenuAnchorType.PrimaryNotEditable, enabled)
                .fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded && enabled, onDismissRequest = { expanded = false }) {
            for (action in GestureAction.entries) {
                DropdownMenuItem(
                    text = {
                        Text(
                            action.label,
                            fontWeight = if (action == selected) FontWeight.SemiBold else null,
                        )
                    },
                    onClick = {
                        onSelect(action)
                        expanded = false
                    },
                    contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                )
            }
        }
    }
}

@Composable
private fun SensitivityCard(
    config: GestureConfig,
    onChange: (GestureConfig) -> Unit,
    onDone: (GestureConfig) -> Unit,
) {
    SectionCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Swipe distance", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            Text("${config.thresholdMm} mm", style = MaterialTheme.typography.titleMedium)
        }
        val vertical = (config.thresholdMm * PAD_HEIGHT_RATIO).roundToInt().coerceAtLeast(1)
        Text(
            "How far your fingers must travel before a swipe counts: ${config.thresholdMm} mm left/right, " +
                "about $vertical mm up/down (the touchpad is half as tall as it is wide). " +
                "Shorter is easier to trigger; longer avoids accidental gestures.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        var latest by remember { mutableStateOf(config) }
        latest = config
        Slider(
            value = config.thresholdMm.toFloat(),
            onValueChange = { onChange(config.copy(thresholdMm = it.roundToInt())) },
            onValueChangeFinished = { onDone(latest) },
            valueRange = 5f..25f,
            steps = 19,
            enabled = config.enabled,
        )
    }
}

@Composable
private fun StatusCard(status: DaemonStatus?) {
    SectionCard(Modifier.fillMaxWidth()) {
        Text("Gesture service", style = MaterialTheme.typography.titleMedium)
        if (status?.started == null) {
            Text(
                "No report from the gesture service yet. It starts at boot " +
                    "(/system/etc/touchpad_gestures.sh); reboot the tablet if you just installed it.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
            return@SectionCard
        }
        StatusRow("Running since", status.started)
        StatusRow("Touchpad", status.device ?: "Not found (Type Cover detached?)")
        HorizontalDivider()
        if (status.lastGesture == null) {
            StatusRow("Last gesture", "None yet. Try a 3-finger swipe up.")
        } else {
            val action = GestureAction.fromId(status.lastAction).label
            StatusRow("Last gesture", "${status.lastGesture} → $action")
            StatusRow("At", status.lastTime ?: "")
        }
    }
}

@Composable
private fun StatusRow(label: String, value: String) {
    Row {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(140.dp),
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
