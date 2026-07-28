allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val rootProjectDir = rootProject.projectDir
tasks.register<Delete>("clean") {
    delete(rootProjectDir.resolve("build"))
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// 2. KODE PENYELAMAT (Wajib ditaruh di sini, SEBELUM evaluationDependsOn)
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileSdk = 36
            }
        }
    }
}

// 3. KUNCI EVALUASI (Wajib ditaruh di PALING BAWAH file)
subprojects {
    project.evaluationDependsOn(":app")
}

//tasks.register<Delete>("clean") {
//    delete(rootProject.layout.buildDirectory)
//}

