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

subprojects {
    project.evaluationDependsOn(":app")
}

// Global fix for legacy plugins that are missing a namespace (e.g. vosk_flutter_2)
allprojects {
    project.plugins.withId("com.android.library") {
        val extension = project.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (extension.namespace == null) {
            if (project.name == "vosk_flutter_2") {
                 extension.namespace = "com.alphacephei.vosk_flutter_2"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
