import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is supplied by CI secrets — keystores/passwords are never committed.
// Sources (first non-empty wins):
//   1. Env vars: ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS,
//      ANDROID_KEY_PASSWORD (the release workflow decodes ANDROID_KEYSTORE_BASE64 into a temp file).
//   2. android/key.properties (gitignored): storeFile, storePassword, keyAlias, keyPassword.
// Without either, release builds fall back to debug signing (local dev only).
val releaseKeyProperties = Properties().apply {
    val propsFile = rootProject.file("key.properties")
    if (propsFile.exists()) {
        propsFile.inputStream().use { load(it) }
    }
}

fun releaseSigningValue(envName: String, propName: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: releaseKeyProperties.getProperty(propName)?.takeIf { it.isNotBlank() }

val releaseStoreFile = releaseSigningValue("ANDROID_KEYSTORE_PATH", "storeFile")?.let { file(it) }
val releaseStorePassword = releaseSigningValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = releaseSigningValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword =
    releaseSigningValue("ANDROID_KEY_PASSWORD", "keyPassword") ?: releaseStorePassword
val hasReleaseSigning = releaseStoreFile?.exists() == true &&
    releaseStorePassword != null && releaseKeyAlias != null && releaseKeyPassword != null
// On CI (CI=true) a release build without the real key fails rather than silently
// shipping a debug-signed APK. Fork-PR CI may opt out via ANDROID_ALLOW_DEBUG_RELEASE_SIGNING=true.
val requireReleaseSigning = System.getenv("ANDROID_REQUIRE_RELEASE_SIGNING") == "true" ||
    (System.getenv("CI") == "true" && System.getenv("ANDROID_ALLOW_DEBUG_RELEASE_SIGNING") != "true")
if (requireReleaseSigning && !hasReleaseSigning) {
    tasks.configureEach {
        if (name == "preReleaseBuild") {
            doFirst {
                throw GradleException(
                    "Release signing required but no keystore configured: set ANDROID_KEYSTORE_PATH, " +
                        "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD (CI secrets)."
                )
            }
        }
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
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // CI secret key when configured; debug key for local-only builds.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
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
