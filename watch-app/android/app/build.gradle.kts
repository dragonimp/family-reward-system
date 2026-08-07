plugins {
    id("com.android.application")
}

android {
    namespace = "net.impx.happylife.watch"
    compileSdk = 35

    defaultConfig {
        applicationId = "net.impx.happylife.watch"
        minSdk = 23
        targetSdk = 35
        versionCode = 100
        versionName = "1.0.0"

        buildConfigField("String", "WATCH_START_URL", "\"https://happylife.ai.impx.net/watch?source=watch-app\"")
    }

    buildFeatures {
        buildConfig = true
    }
}
