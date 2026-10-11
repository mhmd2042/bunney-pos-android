plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.bunney.bunney_pos_android"
    // Pinned explicitly rather than taken from flutter.compileSdkVersion.
    // flutter_plugin_android_lifecycle (pulled in transitively by file_picker)
    // declares an AAR metadata floor of 36, and Gradle fails the build when a
    // dependency compiles against an older API level. Flutter's default is
    // already 36 today, but pinning it means a future Flutter bump cannot
    // silently lower it back and break the build again.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.bunney.bunney_pos_android"
        // Android 7.0. Deliberately low: a café's tablet is often an older
        // device, and nothing here needs a newer API. Bluetooth printing asks
        // for BLUETOOTH_CONNECT only on API 31+, which permission_handler
        // handles by version.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Replace with a real signing config before distributing.
            // Signing with the debug keys for now, so `flutter run --release`
            // and `flutter build apk --release` work out of the box.
            signingConfig = signingConfigs.getByName("debug")
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
