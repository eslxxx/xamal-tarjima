import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 签名配置。key.properties 和 keystore 都不进 git (见 .gitignore)。
// 文件缺失时不报错, 只是 release 继续用 debug 签名 —— 这样别人 clone 下来
// 也能直接 `flutter build apk`, 不会卡在签名上。
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseSigning = keystoreProperties.getProperty("storeFile") != null &&
        file(keystoreProperties.getProperty("storeFile")!!).exists()

android {
    namespace = "com.tilmach.translate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tilmach.translate"
        // minSdk 26 (Android 8.0): 与 libmtcore.so 的编译目标一致。
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // 只出 arm64-v8a。STQ1_0 kernel 用 vqtbl2q_u8 等 aarch64-only intrinsics,
            // 32 位 ARM 跑不了; x86 只有慢的标量回退路径, 模拟器上没有实用价值。
            abiFilters += listOf("arm64-v8a")
        }
    }

    // libmtcore.so 由 engine/scripts/build_engine_android.sh 单独编译,
    // 通过 jniLibs 打进 APK, 不让 Gradle 每次都去编 llama.cpp (那要几分钟)。
    // 更新原生库: bash engine/scripts/sync_jnilibs.sh
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // libmtcore.so 需要以真实文件形式落到 APK 里, 不能被压缩后再解 ——
            // 我们靠 System.loadLibrary 直接加载。
            useLegacyPackaging = false

            // abiFilters 管不住来自依赖 AAR 的 .so: 之前的包里漏进了
            // lib/armeabi-v7a/libdartjni.so 和 lib/x86_64/libdartjni.so。
            // 只要这两个目录存在, Android 就认为这个 APK 支持 32 位 ARM 和 x86_64,
            // 于是能装到那种手机上 —— 但 libflutter.so / libmtcore.so 只有 arm64 一份,
            // 一启动就崩。宁可让系统直接拒绝安装, 也别装上去闪退。
            excludes += setOf(
                "lib/armeabi-v7a/**", "lib/armeabi/**",
                "lib/x86/**", "lib/x86_64/**",
                "lib/mips/**", "lib/mips64/**", "lib/riscv64/**",
            )
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
                storeType = keystoreProperties.getProperty("storeType") ?: "PKCS12"
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // 显式开 v2 + v3。v3 支持密钥轮换 —— 万一将来密钥泄露, 有 v3 才
                // 有可能在不改包名的前提下换密钥。默认只开了 v2。
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // 没有 keystore 时退回 debug 签名, 至少能装能测
                signingConfigs.getByName("debug")
            }
            // R8 暂不开: 收益约 1MB, 但 Flutter + FFI 的组合下多一层被裁错的风险,
            // 而这个 App 的体积瓶颈是 440MB 的模型, 不是 22MB 的 APK。
            isMinifyEnabled = false
            isShrinkResources = false
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
