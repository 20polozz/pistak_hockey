import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Must be signed with the SAME key as the phone app: reuse android/key.properties.
val phoneAndroidDir = rootProject.file("../android")
val keyProps = Properties().apply {
    val f = File(phoneAndroidDir, "key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile") != null

android {
    namespace = "cat.pistak.wear"
    compileSdk = 36

    defaultConfig {
        // Same applicationId as the phone app: required by the Wearable Data
        // Layer to pair both apps (and signed with the same key).
        applicationId = "cat.pistak.app"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // storeFile in key.properties is relative to android/app (Flutter convention).
                val path = keyProps.getProperty("storeFile")
                storeFile = File(path).let { if (it.isAbsolute) it else File(File(phoneAndroidDir, "app"), path) }
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures { compose = true }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.compose.ui:ui-tooling-preview:1.8.3")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
}
