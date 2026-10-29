import java.util.Base64
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Cargar propiedades del keystore
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// API key de Google Maps SDK desde config/env.json (no versionado)
val envFile = rootProject.file("../config/env.json")
@Suppress("UNCHECKED_CAST")
val envConfig: Map<String, Any?> = if (envFile.exists()) {
    groovy.json.JsonSlurper().parse(envFile) as Map<String, Any?>
} else {
    logger.warn("config/env.json no existe: el mapa no tendrá API key. Ver config/env.example.json")
    emptyMap()
}

// Inyecta las claves de config/env.json como --dart-define aunque el comando
// de compilación no incluya --dart-define-from-file (flutter build apk,
// flutter run, etc.). Flutter las recibe en la propiedad "dart-defines",
// cada una como "CLAVE=valor" codificada en base64 y separadas por coma.
run {
    val encoder = Base64.getEncoder()
    val decoder = Base64.getDecoder()
    val current = (project.findProperty("dart-defines") as? String)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?: emptyList()
    val definedKeys = current.map { String(decoder.decode(it)).substringBefore("=") }.toSet()
    val missing = envConfig
        .filterKeys { it !in definedKeys }
        .map { (key, value) -> encoder.encodeToString("$key=$value".toByteArray()) }
    if (missing.isNotEmpty()) {
        project.extra["dart-defines"] = (current + missing).joinToString(",")
    }
}

android {
    namespace = "com.wherecargo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    // Configuración de firma para release
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.wherecargo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["googleMapsApiKey"] =
            envConfig["GOOGLE_MAPS_API_KEY"]?.toString() ?: ""
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Temporalmente deshabilitado hasta solucionar problemas de R8
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
