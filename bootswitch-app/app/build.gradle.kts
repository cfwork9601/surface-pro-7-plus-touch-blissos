plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.surface.bootswitch"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.surface.bootswitch"
        minSdk = 33          // Bliss OS 16 = Android 13; only targets this tablet
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}
