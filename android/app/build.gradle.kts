plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fcxray.client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable application ID; forks should choose their own namespace.
        applicationId = "com.fcxray.client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseKeystore = System.getenv("FCXRAY_KEYSTORE_PATH")
    if (!releaseKeystore.isNullOrBlank()) {
        signingConfigs.create("tagRelease") {
            storeFile = file(releaseKeystore)
            storePassword = System.getenv("FCXRAY_STORE_PASSWORD")
            keyAlias = System.getenv("FCXRAY_KEY_ALIAS")
            keyPassword = System.getenv("FCXRAY_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("tagRelease") ?: signingConfigs.getByName("debug")
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

dependencies { implementation(files(System.getenv("FCXRAY_ANDROID_AAR") ?: "libs/xray.aar")) }
