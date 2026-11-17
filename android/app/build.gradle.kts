import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. android/key.properties is gitignored; if it's missing
// (e.g. a fresh clone), release builds fall back to the debug key.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.arun.minimal_launcher"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        aidl = true // privileged/IPrivilegedService.aidl
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.arun.minimal_launcher"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // `-P debugSigned=true`: a full-speed release build signed with the
            // debug key, so it installs over the debug-key app on the phone
            // (keeping its data). Otherwise the personal release key.
            val debugSigned = project.findProperty("debugSigned") == "true"
            signingConfig = signingConfigs.getByName(if (hasReleaseKey && !debugSigned) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Shizuku: lets the app run a few adb-level operations (disable/enable
    // system apps) without root. https://github.com/RikkaApps/Shizuku-API
    val shizukuVersion = "13.1.5"
    implementation("dev.rikka.shizuku:api:$shizukuVersion")
    implementation("dev.rikka.shizuku:provider:$shizukuVersion")

    // Instant search: Google's QR scanner (its own camera screen, from Play
    // services: no camera permission here) and FileProvider for sharing images.
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation("androidx.core:core:1.13.1")

    // Instant search's camera: a live viewfinder that goes straight to search.
    val cameraxVersion = "1.6.1"
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")
    implementation("androidx.activity:activity:1.9.0")

    // Phone-stats widget: Bluetooth devices' battery levels are a hidden
    // (system) getter that only checks BLUETOOTH_CONNECT.
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:4.3")

    // Hold-to-search's Incognito: its pages in their own web profile
    // (cookies, storage, cache), deleted when it closes.
    implementation("androidx.webkit:webkit:1.12.1")
}
