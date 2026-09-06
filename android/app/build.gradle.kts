import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")

    // Firebase
    id("com.google.gms.google-services")

    id("kotlin-android")

    // Flutter
    id("dev.flutter.flutter-gradle-plugin")
}

// Credenciales de firma release. Vive en android/key.properties, fuera del
// repo (ver android/.gitignore).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    namespace = "com.example.trivia_ia_flutter"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // 🔥 NECESARIO para flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.trivia_ia_flutter"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Sin key.properties no hay clave de subida: se firma con la
                // debug key y Play rechazará el AAB. Solo sirve para pruebas
                // locales de release.
                // Por stderr y no por `logger.warn`/`logger.lifecycle`:
                // `flutter build` filtra la salida de Gradle y ninguno de los
                // dos llegaba a verse, así que el aviso existía y no servía
                // de nada — se podía generar un AAB con la debug key y no
                // enterarse hasta que Play lo rechazara. stderr sí pasa.
                System.err.println(
                    "\n**********************************************************\n" +
                        "AVISO: android/key.properties no existe.\n" +
                        "Este build se firma con la DEBUG KEY y NO es publicable\n" +
                        "en Play. Solo sirve para pruebas locales de release.\n" +
                        "**********************************************************\n"
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {

    // 🔥 NECESARIO para desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}

flutter {
    source = "../.."
}