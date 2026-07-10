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
                    val commonExtClass = Class.forName("com.android.build.api.dsl.CommonExtension")
                    val getNamespaceMethod = commonExtClass.getMethod("getNamespace")
                    val namespaceObj = getNamespaceMethod.invoke(ext)
                    if (namespaceObj == null) {
                        val setNamespaceMethod = commonExtClass.getMethod("setNamespace", String::class.java)
                        setNamespaceMethod.invoke(ext, project.group.toString())
                    }
                } catch (e: Exception) {
                    // ignore
                }
                try {
                    val baseExtClass = Class.forName("com.android.build.gradle.BaseExtension")
                    val setBuildToolsMethod = baseExtClass.getMethod("setBuildToolsVersion", String::class.java)
                    setBuildToolsMethod.invoke(ext, "35.0.0")
                } catch (e: Exception) {
                    // ignore
                }
                try {
                    val baseExtClass = Class.forName("com.android.build.gradle.BaseExtension")
                    val getCompileOptionsMethod = baseExtClass.getMethod("getCompileOptions")
                    val compileOptions = getCompileOptionsMethod.invoke(ext)
                    
                    try {
                        val setSource = compileOptions.javaClass.getMethod("setSourceCompatibility", org.gradle.api.JavaVersion::class.java)
                        setSource.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_17)
                    } catch (e: Exception) {
                        try {
                            val setSource = compileOptions.javaClass.getMethod("setSourceCompatibility", Any::class.java)
                            setSource.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_17)
                        } catch (e2: Exception) {
                            // ignore
                        }
                    }
                    
                    try {
                        val setTarget = compileOptions.javaClass.getMethod("setTargetCompatibility", org.gradle.api.JavaVersion::class.java)
                        setTarget.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_17)
                    } catch (e: Exception) {
                        try {
                            val setTarget = compileOptions.javaClass.getMethod("setTargetCompatibility", Any::class.java)
                            setTarget.invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_17)
                        } catch (e2: Exception) {
                            // ignore
                        }
                    }
                } catch (e: Exception) {
                    // ignore
                }
            }
        }
    }
    
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
    
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}


