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
    namespace = "com.shnell.app"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.shnell.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
  
        
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
    getDefaultProguardFile("proguard-android.txt"), 
    "pro-guard-rules.pro"
)
        }
    }
}

flutter {
    source = "../.."
}
// android/app/build.gradle.kts

dependencies {
    // ... (votre ligne 'platform' BOM existante, si elle est là)
    
    // 🛑 REMPLACER par une version fixe pour résoudre le 'Could not find...'
    // Utilisez la version 24.0.0 comme point de départ.
    implementation("com.google.firebase:firebase-messaging-ktx:24.0.0") 
    
    // ... (autres dépendances)
}