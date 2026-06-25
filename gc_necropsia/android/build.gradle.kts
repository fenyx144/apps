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

// Algunos plugins antiguos (ej. `vosk_flutter`) no declaran `namespace` y fallan con AGP 8+.
// Aquí lo fijamos de forma puntual sin modificar el cache de Pub.
subprojects {
    if (name != "vosk_flutter") return@subprojects

    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android") ?: return@withId
        val getNamespace = androidExt.javaClass.methods.firstOrNull { it.name == "getNamespace" }
        val setNamespace =
            androidExt.javaClass.methods.firstOrNull {
                it.name == "setNamespace" && it.parameterTypes.size == 1 && it.parameterTypes[0] == String::class.java
            }

        val current = (getNamespace?.invoke(androidExt) as? String).orEmpty()
        if (current.isBlank()) setNamespace?.invoke(androidExt, "org.vosk.vosk_flutter")
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
