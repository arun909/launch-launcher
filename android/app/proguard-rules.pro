# Shizuku instantiates the privileged service by class name in its own
# process, so R8 must keep it (and its AIDL stub) intact.
-keep class com.arun.minimal_launcher.privileged.** { *; }
