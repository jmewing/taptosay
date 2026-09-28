import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jmewing.taptosay"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jmewing.taptosay"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing: load credentials from android/key.properties
            // (gitignored) so the APK is signed with a real release key. A
            // debug-signed APK is REJECTED by device-owner QR provisioning.
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
            }
            val ksStoreFile = keystoreProperties.getProperty("storeFile")
            val ksStorePassword = keystoreProperties.getProperty("storePassword")
            val ksKeyAlias = keystoreProperties.getProperty("keyAlias")
            val ksKeyPassword = keystoreProperties.getProperty("keyPassword")
            if (ksStoreFile != null && ksStorePassword != null && ksKeyAlias != null && ksKeyPassword != null) {
                signingConfig = signingConfigs.create("release") {
                    storeFile = file(ksStoreFile)
                    storePassword = ksStorePassword
                    keyAlias = ksKeyAlias
                    keyPassword = ksKeyPassword
                }
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
