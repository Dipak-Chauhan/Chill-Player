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
    afterEvaluate {
        if (project.hasProperty("android")) {
            val ext = project.extensions.findByName("android")
            if (ext != null) {
                try {
                    val namespaceObj = ext.javaClass.getMethod("getNamespace").invoke(ext)
                    if (namespaceObj == null) {
                        ext.javaClass.getMethod("setNamespace", String::class.java).invoke(ext, project.group.toString())
                    }
                } catch (e: Exception) {
                    // ignore
                }
            }
        }
    }
    
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        val target = when (project.name) {
            "app", "path_provider_android", "shared_preferences_android", "wakelock_plus", "wakelock_plus_platform_interface", "package_info_plus", "package_info_plus_platform_interface" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            "audio_session" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
            else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
        }
        compilerOptions.jvmTarget.set(target)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
