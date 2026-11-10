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
// Some plugins (tflite_flutter) compile their Java for JVM 11 but leave Kotlin
// on the JDK default, which Gradle rejects as inconsistent. Compile each
// project's Kotlin for the same JVM target as its Java.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        val javaTask = project.tasks.findByName(name.replace("Kotlin", "JavaWithJavac")) as? JavaCompile
        if (javaTask != null) {
            compilerOptions.jvmTarget.set(
                project.provider {
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(javaTask.targetCompatibility)
                },
            )
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}