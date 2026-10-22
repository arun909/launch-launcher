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
}
