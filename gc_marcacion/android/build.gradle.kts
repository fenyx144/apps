import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Plugins en Pub (geocoding_android, vosk_flutter, …) que aún declaran compileSdk 33;
// AndroidX reciente exige API 34+. Mismo criterio que gc_bioseguridad, con afterEvaluate
// para que el override aplique también a build.gradle Groovy de Pub.
subprojects {
    afterEvaluate {
        val androidLib = extensions.findByType(LibraryExtension::class.java) ?: return@afterEvaluate
        if (androidLib.compileSdk == null || androidLib.compileSdk!! < 34) {
            androidLib.compileSdk = 35
        }
        if (name == "vosk_flutter" && androidLib.namespace.isNullOrBlank()) {
            androidLib.namespace = "org.vosk.vosk_flutter"
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
