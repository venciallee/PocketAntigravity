import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.skie)
}

kotlin {
    jvm {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    val xcf = XCFramework("AntigravityShared")
    listOf(
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "AntigravityShared"
            isStatic = true
            export(project(":shared:core-model"))
            export(project(":shared:core-protocol"))
            export(project(":shared:core-markdown"))
            export(project(":shared:core-domain"))
            xcf.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":shared:core-model"))
            api(project(":shared:core-protocol"))
            api(project(":shared:core-markdown"))
            api(project(":shared:core-domain"))
            api(libs.kotlinx.coroutines.core)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}
