package com.arun.minimal_launcher.privileged

import android.content.Context
import kotlin.system.exitProcess

/**
 * Shizuku "user service": runs in a separate process started by Shizuku with
 * shell (adb) uid, NOT inside the app. It has the same powers as
 * `adb shell`, so it exposes only what's in [IPrivilegedService].
 *
 * Commands run via ProcessBuilder with an argument array (no shell), and
 * package names are validated, so input can't be turned into extra commands.
 */
class PrivilegedService() : IPrivilegedService.Stub() {

    /** Shizuku uses this constructor when available. */
    @Suppress("UNUSED_PARAMETER")
    constructor(context: Context) : this()

    override fun destroy() {
        exitProcess(0)
    }

    override fun setPackageEnabled(packageName: String, enabled: Boolean, userId: Int): String? {
        if (!PACKAGE_NAME.matches(packageName)) return "Invalid package name"
        if (userId < 0) return "Invalid user"
        val action = if (enabled) "enable" else "disable-user"
        return run("pm", action, "--user", userId.toString(), packageName)
    }

    /** Returns null if the command succeeded, else its output. */
    private fun run(vararg command: String): String? {
        return try {
            val process = ProcessBuilder(*command).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText().trim()
            val exit = process.waitFor()
            // pm prints "Package x new state: disabled-user" on success; some
            // failures still exit 0 but print an Exception/Error.
            if (exit == 0 && !output.contains("Exception") && !output.startsWith("Error")) null
            else output.ifEmpty { "pm exited with code $exit" }
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
    }

    companion object {
        private val PACKAGE_NAME = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")
    }
}
