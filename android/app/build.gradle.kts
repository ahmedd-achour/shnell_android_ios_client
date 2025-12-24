import java.util.Properties
import java.io.FileInputStream

// 1. Move the property loading to the top of the file
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin") // <--- This MUST be present
}

android {
    namespace = "com.shnell.app"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    // 2. Define the signingConfigs block BEFORE buildTypes
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.shnell.app"
        minSdk = 23
        targetSdk = 35 
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
buildTypes {
    getByName("release") {
        // You must enable code shrinking (minify) to use resource shrinking
        isMinifyEnabled = true 
        isShrinkResources = true 
        
        signingConfig = signingConfigs.getByName("release")
        
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}
}