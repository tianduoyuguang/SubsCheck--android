plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.subscheck.subscheck"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.subscheck.subscheck"
        minSdk = flutter.minSdkVersion
        // 关键：内核是 GOOS=linux 的静态 ET_EXEC（非 PIE），
        // Android 10+ 只有在 targetSdk < 29 时才允许从可写目录 exec，故锁死 28。
        targetSdk = 28
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 允许用 -PtargetAbi=arm64-v8a,armeabi-v7a 限定打包的 ABI；
        // 默认全打（调试用 x86_64 走模拟器验证）。
        val abiFilter = (project.findProperty("targetAbi") as String?)?.trim().orEmpty()
        if (abiFilter.isNotEmpty()) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(abiFilter.split(",").map { it.trim() }.filter { it.isNotEmpty() })
            }
        }
    }

    // 内核以 lib*.so 形式打进 jniLibs，构建时会被压缩进 APK；
    // 必须让它解压到 nativeLibraryDir 才能直接 exec。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += setOf("META-INF/*.kotlin_module")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    signingConfigs {
        create("release") {
            // 正式签名，keystore 放在 android/keystore/ 下（不进版本库）。
            val storePath = rootProject.file("keystore/subscheck-release.jks")
            if (storePath.exists()) {
                storeFile = storePath
                storePassword = "subscheck2026"
                keyAlias = "subscheck"
                keyPassword = "subscheck2026"
            }
        }
    }

    buildTypes {
        release {
            // keystore 存在就用正式签名，否则回落到 debug 签名保证能出包。
            val release = signingConfigs.findByName("release")
            signingConfig = if (release?.storeFile != null) release else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
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
