allprojects {
    repositories {
        // Flutter 引擎产物（io.flutter:xxx_release/debug）专用镜像仓。
        // 不显式声明的话 Gradle 会回落到 repo.maven.apache.org，
        // 而那里根本没有 io.flutter 的 release 包，只会超时。
        maven {
            url = uri("https://storage.flutter-io.cn/download.flutter.io")
            content {
                includeGroup("io.flutter")
                includeGroup("io.flutter.embedding")
            }
        }
        // 国内镜像优先（按用户要求走镜像源）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
