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

// Evita :file_picker:lintVitalAnalyzeRelease (e similares) falharem no Windows com
// "O arquivo já está sendo usado por outro processo" ao acessar o cache do lint.
subprojects {
    tasks.whenTaskAdded {
        if (name.startsWith("lintVital")) {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
    // Saídas típicas do APK (relativo à pasta android/)
    delete(file("../build/app/outputs/flutter-apk"))
    delete(file("../build/app/outputs/apk"))
}
