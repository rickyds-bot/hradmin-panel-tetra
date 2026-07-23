plugins {
    id("com.android.application")
    // Add the dependency for the Google services Gradle plugin
    id("com.google.gms.google-services") version "4.5.0" apply false

    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mobile_absensi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures {
        resValues = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

defaultConfig {
        // Sesuaikan applicationId dengan ID awal aplikasi Anda
        applicationId = "com.tetra.absensi" 
        minSdk = flutter.minSdkVersion
        compileSdk = 36
        targetSdk = 36
        
        // --- INI YANG KITA PERBAIKI ---
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "app"

    productFlavors {
        create("admin") {
            dimension = "app"
            applicationId = "com.tetra.admin"
            resValue("string", "app_name", "Admin Tetra")
        }
        create("karyawan") {
            dimension = "app"
            applicationId = "com.tetra.absensi"
            resValue("string", "app_name", "Absensi Tetra")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}