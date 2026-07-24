import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Stable release signing (same pattern as Flowlog). Required so Obtainium can
// update over previous CI builds. Debug keystores change every runner → Conflict.
val uploadKeystoreProperties = Properties().apply {
    val propsFile = rootProject.file("upload-key.properties")
    if (propsFile.exists()) {
        propsFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.isyourbrainfoss.progressor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.isyourbrainfoss.progressor"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            val alias = uploadKeystoreProperties.getProperty("keyAlias")
            val storePw = uploadKeystoreProperties.getProperty("storePassword")
            val keyPw = uploadKeystoreProperties.getProperty("keyPassword")
            val storePath = uploadKeystoreProperties.getProperty("storeFile")
            if (alias != null && storePw != null && keyPw != null && storePath != null) {
                keyAlias = alias
                storePassword = storePw
                keyPassword = keyPw
                storeFile = rootProject.file(storePath)
            }
        }
    }

    buildTypes {
        release {
            // Prefer stable upload key when present; fall back to debug for local-only builds.
            val upload = signingConfigs.findByName("upload")
            signingConfig = if (upload?.storeFile != null && upload.storeFile!!.exists()) {
                upload
            } else {
                signingConfigs.getByName("debug")
            }
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
