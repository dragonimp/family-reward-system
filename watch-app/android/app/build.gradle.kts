plugins {
    id("com.android.application")
}

val watchKeystorePath = providers.environmentVariable("HAPPYLIFE_WATCH_KEYSTORE").orNull
val watchKeyAlias = providers.environmentVariable("HAPPYLIFE_WATCH_KEY_ALIAS").orNull
val watchKeystorePassword = providers.environmentVariable("HAPPYLIFE_WATCH_KEYSTORE_PASSWORD").orNull
val watchKeyPassword = providers.environmentVariable("HAPPYLIFE_WATCH_KEY_PASSWORD").orNull
val watchSigningReady = listOf(
    watchKeystorePath,
    watchKeyAlias,
    watchKeystorePassword,
    watchKeyPassword
).all { !it.isNullOrBlank() }

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

    signingConfigs {
        if (watchSigningReady) {
            create("release") {
                storeFile = file(watchKeystorePath!!)
                storePassword = watchKeystorePassword!!
                keyAlias = watchKeyAlias!!
                keyPassword = watchKeyPassword!!
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            if (watchSigningReady) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val requestsReleaseArtifact = allTasks.any {
        it.path.endsWith("assembleRelease", ignoreCase = true) ||
            it.path.endsWith("bundleRelease", ignoreCase = true)
    }
    if (requestsReleaseArtifact && !watchSigningReady) {
        throw GradleException(
            "Release signing requires HAPPYLIFE_WATCH_KEYSTORE, HAPPYLIFE_WATCH_KEY_ALIAS, " +
                "HAPPYLIFE_WATCH_KEYSTORE_PASSWORD and HAPPYLIFE_WATCH_KEY_PASSWORD"
        )
    }
}
