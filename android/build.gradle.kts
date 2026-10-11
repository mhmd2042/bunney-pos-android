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

// Some plugins in the offline cache (file_picker 8.3.7) declare an older
// compileSdk than the AAR metadata floor their own transitive dependency
// (flutter_plugin_android_lifecycle 2.0.35) requires, and Gradle fails the
// whole build on the mismatch. Raising every Android subproject to the same
// level the app uses resolves it without patching the cache, which would not
// survive a `pub get`.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (compileSdk == null || compileSdk!! < 36) {
                compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
