package dev.surface.bootswitch

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle

/**
 * Asks for confirmation, then runs /system/etc/boot_to_windows.sh as root
 * (via KernelSU `su`). The script sets UEFI BootNext to Windows Boot Manager
 * and reboots, so only the next boot goes to Windows.
 */
class MainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlertDialog.Builder(this)
            .setTitle("Restart into Windows?")
            .setMessage("Unsaved work in open apps will be lost. The tablet boots Windows once; " +
                "use \"Boot to Bliss\" in Windows to come back.")
            .setPositiveButton("Restart") { _, _ -> restart() }
            .setNegativeButton("Cancel") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun restart() {
        Thread {
            val error = try {
                val p = ProcessBuilder("su", "-c", SCRIPT).redirectErrorStream(true).start()
                val out = p.inputStream.bufferedReader().readText().trim()
                if (p.waitFor() == 0) null else out.ifEmpty { "Exit code ${p.exitValue()}" }
            } catch (e: Exception) {
                e.message ?: e.toString()
            }
            if (error != null) runOnUiThread { showError(error) }
        }.start()
    }

    private fun showError(message: String) {
        AlertDialog.Builder(this)
            .setTitle("Couldn't switch to Windows")
            .setMessage("$message\n\nMake sure Boot Switch has root access in the KernelSU app " +
                "(Superuser tab), and that $SCRIPT is installed.")
            .setPositiveButton("OK") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    companion object {
        const val SCRIPT = "/system/etc/boot_to_windows.sh"
    }
}
