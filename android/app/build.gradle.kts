plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.merr.fileinfra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "cc.merr.fileinfra"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystoreFilePath = System.getenv("KEYSTORE_FILE")
            if (!keystoreFilePath.isNullOrBlank()) {
                storeFile = file(keystoreFilePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
                // The existing signing key retains its original alias after the app rename.
                keyAlias = System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() } ?: "inout"
                keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            }
        }
    }

    buildTypes {
        release {
            // Fail fast on CI/local release builds when keystore env is
            // missing — silently falling back to the debug keystore (the
            // previous behavior) ships a debug-signed APK to the release
            // channel, which can never be OTA-upgraded by users who
            // installed it.
            val keystoreFile: String? = System.getenv("KEYSTORE_FILE")
            // F-Droid signs the APK after building it. Keep unsigned builds an
            // explicit opt-in so normal release builds still require our key.
            val unsignedRelease = System.getenv("FILEINFRA_UNSIGNED_RELEASE") == "1"
            signingConfig = if (unsignedRelease) {
                null
            } else if (!keystoreFile.isNullOrBlank()) {
                signingConfigs.getByName("release")
            } else if (gradle.startParameter.taskNames.any {
                    it.contains("Release", ignoreCase = true) ||
                        it.contains("Bundle", ignoreCase = true)
                }) {
                throw GradleException(
                    "KEYSTORE_FILE env must be set for release builds. " +
                        "See scripts/docker_build_android.sh or the CI secret setup."
                )
            } else {
                // Non-release tasks (e.g. assembleDebug picking up release
                // configuration as a side effect) still get debug signing.
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
