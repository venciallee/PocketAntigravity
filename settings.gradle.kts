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
        mavenCentral()
    }
}

rootProject.name = "AntigravityMobile"

include(":shared:core-model")
include(":shared:core-protocol")
include(":shared:core-markdown")
include(":shared:umbrella")
