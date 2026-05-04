plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.courier_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        // 🔹 ВКЛЮЧАЕМ DESUGARING ДЛЯ ПОДДЕРЖКИ НОВЫХ ФУНКЦИЙ JAVA (нужно для уведомлений)
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID
        applicationId = "com.example.courier_app"

        // minSdk 23 — это отлично, подходит для пушей
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// 🔹 ДОБАВЛЯЕМ ЗАВИСИМОСТЬ ДЛЯ DESUGARING В КОНЦЕ ФАЙЛА
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")}