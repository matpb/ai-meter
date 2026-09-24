import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.gms.google-services")
}

android {
    namespace = "org.mat.aimeter"
    compileSdk = 36

    defaultConfig {
        applicationId = "org.mat.aimeter"
        minSdk = 26
        targetSdk = 36
        versionCode = 5
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        val aiMeterTopic = (project.findProperty("aiMeterTopic") as String?) ?: "meters"
        buildConfigField("String", "FCM_TOPIC", "\"$aiMeterTopic\"")

        // Falls back to local.properties so the key never needs to live in a committed file.
        val localProps = Properties().apply {
            val localFile = rootProject.file("local.properties")
            if (localFile.exists()) localFile.inputStream().use { load(it) }
        }
        val aiMeterRefreshKey = (project.findProperty("aiMeterRefreshKey") as String?)
            ?: localProps.getProperty("aiMeterRefreshKey")
            ?: ""
        buildConfigField("String", "REFRESH_KEY", "\"$aiMeterRefreshKey\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.07.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.core:core-ktx:1.17.0")

    implementation("androidx.glance:glance:1.1.1")
    implementation("androidx.glance:glance-appwidget:1.1.1")

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")

    implementation(platform("com.google.firebase:firebase-bom:34.14.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-database")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
    implementation("androidx.work:work-runtime-ktx:2.10.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
}
