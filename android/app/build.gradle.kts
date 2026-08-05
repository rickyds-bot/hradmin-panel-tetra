plugins {
    id("com.android.application")
    id("com.google.gms.google-services") // Tanpa version & apply false di level app
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tetra.absensi"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    
    buildFeatures {
        buildConfig = true
        resValues = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    // --- PASTIKAN SEMUA BAGIAN INI BERADA DI DALAM BLOK android {} ---
    defaultConfig {
        applicationId = "com.tetra.absensi"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
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
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
        
   


flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}