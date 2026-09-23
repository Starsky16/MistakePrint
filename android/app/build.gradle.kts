import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 签名材料一律从 `d:\code\keystore` 引用，仓库内不存密钥副本。
// `android/key.properties` 已 gitignore，且只记路径不记口令：口令在构建期从 keystore
// 目录下的共用口令文件读取，因此整机口令始终只有一份。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// 先认字面量键（兼容 Flutter 模板的标准写法），再退回「路径键 + 读文件」。
fun keystoreSecret(literalKey: String, pathKey: String): String? {
    keystoreProperties.getProperty(literalKey)?.let { return it }
    val path = keystoreProperties.getProperty(pathKey) ?: return null
    val file = File(path)
    if (!file.exists()) return null
    return file.readText().trim()
}

val releaseStorePath = keystoreProperties.getProperty("storeFile")
val hasReleaseKeystore = releaseStorePath != null && File(releaseStorePath).exists()

android {
    namespace = "com.starksky16.mistake_print"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.starksky16.mistake_print"
        // 热敏打印与离屏渲染管线要求的最低版本，固定不随 Flutter 模板漂移。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = File(releaseStorePath!!)
                storePassword = keystoreSecret("storePassword", "storePasswordFile")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreSecret("keyPassword", "keyPasswordFile")
            }
        }
    }

    buildTypes {
        release {
            // 拿不到 keystore（例如干净 clone 且没建 key.properties）时回落 debug 签名，
            // 保证 `flutter run --release` 仍可用；正式发版必须让 hasReleaseKeystore 为真。
            signingConfig = if (hasReleaseKeystore) {
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
