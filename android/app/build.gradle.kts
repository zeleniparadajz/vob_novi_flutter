import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter reads dart-defines after project evaluation; keep the shared key local.
val diagnosticsProperties = Properties().apply {
    val settings = rootProject.file("diagnostics.properties")
    if (settings.exists()) settings.inputStream().use { load(it) }
}
val buildDefines = linkedMapOf<String, String>()
(project.findProperty("dart-defines")?.toString() ?: "")
    .split(',').filter { it.isNotBlank() }.forEach { encoded ->
        val define = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        val separator = define.indexOf('=')
        if (separator > 0) buildDefines[define.substring(0, separator)] = define.substring(separator + 1)
    }
val diagnosticsKey = buildDefines["DIAGNOSTICS_UPLOAD_KEY"]
    ?: System.getenv("VOB_DIAGNOSTICS_KEY")
    ?: diagnosticsProperties.getProperty("uploadKey")
if (diagnosticsKey.isNullOrBlank() || diagnosticsKey.length < 32) {
    throw GradleException("Online logovi zahtijevaju isti kljuc kao server: android/diagnostics.properties (uploadKey), VOB_DIAGNOSTICS_KEY ili --dart-define=DIAGNOSTICS_UPLOAD_KEY.")
}
buildDefines["DIAGNOSTICS_UPLOAD_KEY"] = diagnosticsKey
diagnosticsProperties.getProperty("baseUrl")?.takeIf { it.isNotBlank() }?.let {
    buildDefines.putIfAbsent("DIAGNOSTICS_BASE_URL", it)
}
extensions.extraProperties["dart-defines"] = buildDefines.entries.joinToString(",") {
    Base64.getEncoder().encodeToString("${it.key}=${it.value}".toByteArray(Charsets.UTF_8))
}

android {
    namespace = "com.vodovodbd.vodovod_bd_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vodovodbd.vodovod_bd_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
