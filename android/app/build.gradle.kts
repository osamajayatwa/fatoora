import java.util.Properties
import groovy.json.JsonSlurper
import java.util.Base64

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") apply false
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val settlementTestDefines = (providers.gradleProperty("dart-defines").orNull ?: "")
    .split(",").filter { it.isNotEmpty() }.associate {
        val parts = String(Base64.getDecoder().decode(it), Charsets.UTF_8).split("=", limit = 2)
        parts[0] to parts.getOrElse(1) { "" }
    }
val settlementTransportTest = settlementTestDefines["FATOORA_SETTLEMENT_TRANSPORT_TEST"] == "true"
if (settlementTransportTest && (settlementTestDefines["FATOORA_ENV"] != "test" ||
        gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) || it.contains("profile", ignoreCase = true) || it.contains("staging", ignoreCase = true) })) {
    throw GradleException("Settlement transport accepts isolated debug emulator builds only.")
}
if (!settlementTransportTest) apply(plugin = "com.google.gms.google-services")

val stagingTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("staging", ignoreCase = true)
}
val stagingOptIn = stagingTaskRequested &&
    (providers.gradleProperty("fatooraStaging").orNull == "true" ||
        System.getenv("ORG_GRADLE_PROJECT_fatooraStaging") == "true")
if (stagingTaskRequested && !stagingOptIn) {
    throw GradleException("Use scripts/staging.ps1 for the isolated staging flavor.")
}
if (stagingOptIn) {
    if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
        throw GradleException("Staging permits debug signing only.")
    }
    val nativeFile = file("src/staging/google-services.json")
    if (!nativeFile.isFile) throw GradleException("Missing staging native Firebase configuration.")
    val native = JsonSlurper().parse(nativeFile) as Map<*, *>
    val project = native["project_info"] as? Map<*, *>
    val clients = native["client"] as? List<*>
    val client = clients?.singleOrNull() as? Map<*, *>
    val info = client?.get("client_info") as? Map<*, *>
    val androidInfo = info?.get("android_client_info") as? Map<*, *>
    val apiKeys = client?.get("api_key") as? List<*>
    val apiKey = (apiKeys?.singleOrNull() as? Map<*, *>)?.get("current_key")
    val defines = (providers.gradleProperty("dart-defines").orNull ?: "")
        .split(",").filter { it.isNotEmpty() }.associate {
            val decoded = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
            val parts = decoded.split("=", limit = 2)
            parts[0] to parts.getOrElse(1) { "" }
        }
    if (project?.get("project_id") != "fatoora-original-staging" ||
        project["project_number"] != "5438538531" ||
        info?.get("mobilesdk_app_id") != "1:5438538531:android:560f7feecdb97bf5240296" ||
        androidInfo?.get("package_name") != "com.fujika.fatoora.original.staging" ||
        defines["FATOORA_ENV"] != "staging" ||
        defines["FIREBASE_PROJECT_ID"] != project["project_id"] ||
        defines["FIREBASE_PROJECT_ID_CONFIRM"] != project["project_id"] ||
        defines["FIREBASE_MESSAGING_SENDER_ID"] != project["project_number"] ||
        defines["FIREBASE_APP_ID"] != info["mobilesdk_app_id"] ||
        defines["FIREBASE_API_KEY"] != apiKey
    ) throw GradleException("Native/Dart staging Firebase targets do not match the pinned registration.")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (!stagingOptIn && !settlementTransportTest && keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}
val requiredSigningProperties = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val missingSigningProperties = requiredSigningProperties.filter {
    keystoreProperties.getProperty(it).isNullOrBlank()
}
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseTaskRequested &&
    (!keystorePropertiesFile.exists() || missingSigningProperties.isNotEmpty())
) {
    throw GradleException(
        "Production release signing is not configured. Copy " +
            "android/key.properties.example to android/key.properties and " +
            "provide storeFile, storePassword, keyAlias, and keyPassword.",
    )
}

android {
    namespace = "com.fujika.fatoora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = if (settlementTransportTest) "com.fujika.fatoora.settlementtest" else "com.fujika.fatoora"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (settlementTransportTest) {
        sourceSets.getByName("debug").manifest.srcFile("src/settlementEmulator/AndroidManifest.xml")
    }

    if (stagingOptIn) {
        flavorDimensions += "environment"
        productFlavors {
            create("staging") {
                dimension = "environment"
                applicationIdSuffix = ".original.staging"
            }
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists() &&
                missingSigningProperties.isEmpty()
            ) {
                storeFile = rootProject.file(
                    keystoreProperties.getProperty("storeFile"),
                )
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

androidComponents {
    beforeVariants(selector().all()) {
        if ((stagingOptIn || settlementTransportTest) && it.buildType != "debug") it.enable = false
    }
}

flutter {
    source = "../.."
}
dependencies {
    // ... your other dependencies

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
