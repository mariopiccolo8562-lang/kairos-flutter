plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun env(name: String): String? = System.getenv(name)?.takeIf { it.isNotBlank() }

// Chiave di firma definitiva: dai segreti di GitHub (come Kairos Lite e Kairos TV).
// Se i segreti non ci sono si usa la chiave di ANTEPRIMA del repository.
val releaseKeystore = env("KS_PATH")?.let { file(it) }?.takeIf { it.exists() }

android {
    namespace = "com.kairos.plus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Kairos Plus: app separata dalle altre app Kairos, si installa accanto a loro
        applicationId = "com.kairos.plus"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            storeFile = file("../keys/preview.jks")
            storePassword = "kairos-preview"
            keyAlias = "preview"
            keyPassword = "kairos-preview"
        }
        create("release") {
            if (releaseKeystore != null) {
                storeFile = releaseKeystore
                storePassword = env("KS_PASS")
                keyAlias = env("KEY_ALIAS")
                keyPassword = env("KEY_PASS")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeystore != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
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
    // lettore nativo: stessa versione collaudata di Kairos Lite e Kairos TV
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.4.1")
    implementation("androidx.media3:media3-ui:1.4.1")
}
