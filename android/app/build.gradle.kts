plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.gms.google-services")
}

android {
    namespace = "org.mat.pocketmeter"
    compileSdk = 36

    defaultConfig {
        applicationId = "org.mat.pocketmeter"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "0.2"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        val aiMeterTopic = (project.findProperty("aiMeterTopic") as String?) ?: "meters"
        buildConfigField("String", "FCM_TOPIC", "\"$aiMeterTopic\"")
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

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
}
