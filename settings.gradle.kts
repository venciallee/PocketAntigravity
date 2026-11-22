import java.util.Properties

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        maven(url = "https://maven-central.storage-download.googleapis.com/maven2")
        mavenCentral()
    }
}

rootProject.name = "AntigravityMobile"

include(":shared:core-model")
include(":shared:core-protocol")
include(":shared:core-markdown")
include(":shared:core-domain")
include(":shared:umbrella")

// Include Android modules automatically whenever an Android SDK is available (Linux CI, Android Studio, devbox),
// while allowing macOS-only iOS XCFramework runners without ANDROID_HOME to stay green.
val skipAndroid = providers.gradleProperty("skipAndroid").orNull?.toBoolean() == true
val forceAndroid = providers.gradleProperty("enableAndroid").orNull?.toBoolean() == true
val localPropsFile = file("local.properties")
val localSdkDir = if (localPropsFile.exists()) {
    Properties().apply { localPropsFile.inputStream().use(::load) }.getProperty("sdk.dir")
} else {
    null
}
val envSdkDir = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
val hasAndroidSdk = !skipAndroid && (
    forceAndroid ||
        (!localSdkDir.isNullOrBlank() && file(localSdkDir).exists()) ||
        (!envSdkDir.isNullOrBlank() && file(envSdkDir).exists())
    )

if (hasAndroidSdk) {
    include(":apps:android:core-ui")
    include(":apps:android:core-platform")
    include(":apps:android:app")
}
