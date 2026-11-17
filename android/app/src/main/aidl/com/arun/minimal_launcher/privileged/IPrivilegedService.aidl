package com.arun.minimal_launcher.privileged;

/**
 * Runs inside Shizuku's process with adb ("shell") privileges.
 *
 * Deliberately narrow: only the operations the app needs, with validated
 * arguments. Never add a generic "run this command" method here.
 */
interface IPrivilegedService {
    /** Shizuku's reserved code for tearing the service down. */
    void destroy() = 16777114;

    /**
     * Enables or disables (pm disable-user) a package for one user.
     * Returns null on success, or an error message.
     */
    String setPackageEnabled(String packageName, boolean enabled, int userId) = 1;

    /**
     * Lets [packageName] change brightness (WRITE_SETTINGS) and display
     * comfort settings such as extra dim (WRITE_SECURE_SETTINGS) itself.
     * Returns null on success, or an error message.
     */
    String grantControlAccess(String packageName) = 2;

    /** Dark theme ("night mode") on or off. Null on success, else an error. */
    String setNightMode(boolean on) = 3;

    /**
     * The ringer mode (AudioManager.RINGER_MODE_*), set the way the system's
     * volume panel does: silent on its own, without turning on Do Not
     * Disturb (which an app's setRingerMode does). Null on success, else an
     * error.
     */
    String setRingerMode(int mode) = 4;

    /** Opens Google's Circle to Search over the screen. Null on success, else an error. */
    String startCircleToSearch() = 5;
}
