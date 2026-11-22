plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "dev.antigravity.android.core.platform"
    compileSdk = 36
    buildToolsVersion = "35.0.0"

    defaultConfig {
        minSdk = 29
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    api(project(":shared:core-model"))
    api(project(":shared:core-protocol"))
    api(project(":shared:core-domain"))

    api(libs.androidx.core.ktx)
    api(libs.androidx.biometric)
    api(libs.androidx.datastore.preferences)
    api(libs.tink.android)
    api(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)
}
