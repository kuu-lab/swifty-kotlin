#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func apkPackagesMavenAndroidLibrariesWithoutGradle() throws {
        try withWorkspace { root in
            let fileManager = FileManager.default
            let tools = root.appendingPathComponent("build-tools/36.1.0", isDirectory: true)
            let platform = root.appendingPathComponent("platforms/android-36.1", isDirectory: true)
            for directory in [tools, platform] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try writeFakeAndroidJar(to: platform.appendingPathComponent("android.jar"), root: root)

            // An AAR as published to Google Maven: classes, resources, a
            // manifest with a startup provider, and jar resources.
            let aar = root.appendingPathComponent("aar", isDirectory: true)
            let classes = root.appendingPathComponent("aar-classes", isDirectory: true)
            for directory in ["META-INF/services", "lib/widget"] {
                try fileManager.createDirectory(at: classes.appendingPathComponent(directory), withIntermediateDirectories: true)
            }
            try fileManager.createDirectory(at: aar.appendingPathComponent("res/values"), withIntermediateDirectories: true)
            let widget = root.appendingPathComponent("Widget.java")
            try "package lib.widget; public class Widget { public String name() { return \"widget\"; } }"
                .write(to: widget, atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", classes.path, widget.path], root: root)
            try "lib.widget.WidgetService\n".write(to: classes.appendingPathComponent("META-INF/services/lib.Service"), atomically: true, encoding: .utf8)
            try "license".write(to: classes.appendingPathComponent("META-INF/LICENSE.txt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("jar", ["cf", aar.appendingPathComponent("classes.jar").path, "-C", classes.path, "."], root: root)
            try "<resources><string name=\"title\">Widget</string></resources>"
                .write(to: aar.appendingPathComponent("res/values/strings.xml"), atomically: true, encoding: .utf8)
            let jni = aar.appendingPathComponent("jni/arm64-v8a", isDirectory: true)
            try fileManager.createDirectory(at: jni, withIntermediateDirectories: true)
            try String(repeating: "compressible native code ", count: 200)
                .write(to: jni.appendingPathComponent("libwidget.so"), atomically: true, encoding: .utf8)
            try """
            <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="lib.widget">
                <application>
                    <provider android:name=".WidgetProvider" android:authorities="${applicationId}.widget" />
                </application>
            </manifest>
            """.write(to: aar.appendingPathComponent("AndroidManifest.xml"), atomically: true, encoding: .utf8)
            let repository = root.appendingPathComponent("repo/org/example/widget/1.0", isDirectory: true)
            try fileManager.createDirectory(at: repository, withIntermediateDirectories: true)
            _ = try jvmTool("jar", ["cfM", repository.appendingPathComponent("widget-1.0.aar").path, "-C", aar.path, "."], root: root)
            try """
            <project><groupId>org.example</groupId><artifactId>widget</artifactId><version>1.0</version>
            <packaging>aar</packaging></project>
            """.write(to: repository.appendingPathComponent("widget-1.0.pom"), atomically: true, encoding: .utf8)

            func writeTool(_ name: String, _ body: String) throws {
                let path = tools.appendingPathComponent(name)
                try ("#!/bin/sh\nset -eu\n" + body + "\n").write(to: path, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
            }
            try writeTool("aapt2", #"""
                operation=$1; shift
                tools=$(dirname "$0")
                if [ "$operation" = compile ]; then
                    while [ "$#" -gt 0 ]; do [ "$1" = -o ] && { : > "$2"; shift; }; shift; done
                    exit 0
                fi
                printf '%s\n' "$@" > "$tools/link-args.txt"
                while [ "$#" -gt 0 ]; do
                    case "$1" in
                        -o) output=$2; shift ;;
                        --manifest) manifest=$2; shift ;;
                        --java) generated=$2; shift ;;
                    esac
                    shift
                done
                cp "$manifest" "$tools/merged.xml"
                mkdir -p "$tools/m" && cp "$manifest" "$tools/m/AndroidManifest.xml"
                (cd "$tools/m" && zip -q "$output" AndroidManifest.xml)
                for package in app lib.widget; do
                    directory="$generated/$(echo "$package" | tr . /)"
                    mkdir -p "$directory"
                    printf 'package %s; public final class R { public static final class string { public static final int title = 0x7f010000; } }\n' "$package" > "$directory/R.java"
                done
                """#)
            try writeTool("d8", #"""
                printf '%s\n' "$@" > "$(dirname "$0")/d8-args.txt"
                for arg do
                    if [ "$arg" = --output ]; then output_next=1
                    elif [ "${output_next:-0}" = 1 ]; then output=$arg; output_next=0; fi
                done
                printf 'test dex' > "$output/classes.dex"
                """#)
            try writeTool("apksigner", #"""
                for arg do
                    if [ "$arg" = --out ]; then output_next=1
                    elif [ "${output_next:-0}" = 1 ]; then output=$arg; output_next=0; fi
                    last=$arg
                done
                cp "$last" "$output"
                """#)

            let manifest = root.appendingPathComponent("AndroidManifest.xml")
            try """
            <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                <application android:label="App" />
            </manifest>
            """.write(to: manifest, atomically: true, encoding: .utf8)
            let keystore = root.appendingPathComponent("debug.keystore")
            try Data().write(to: keystore)
            let input = root.appendingPathComponent("Main.kt")
            try "package app\nfun label(): String = lib.widget.Widget().name() + Bridge.mark()\n"
                .write(to: input, atomically: true, encoding: .utf8)
            // A Java source using kotlin.* needs the runtime jar before Sema,
            // even when no earlier compilation installed its provider.
            let bridge = root.appendingPathComponent("Bridge.java")
            try "package app; public final class Bridge { public static String mark() { return kotlin.Unit.INSTANCE.toString(); } }"
                .write(to: bridge, atomically: true, encoding: .utf8)
            AndroidBuildInputs.runtimeJarProvider = nil
            let output = root.appendingPathComponent("app.apk")
            var android = AndroidOptions(sdkPath: root.path, manifestPath: manifest.path, keystorePath: keystore.path)
            android.dependencies = ["org.example:widget:1.0"]
            android.mavenRepositories = [root.appendingPathComponent("repo").absoluteString]
            android.mavenCachePath = root.appendingPathComponent("maven-cache").path
            android.namespace = "app"
            android.applicationID = "app.debug"
            android.targetSdk = 34
            android.debuggable = true
            android.javaSources = [bridge.path]
            let options = CompilerOptions(
                moduleName: "LibraryApp", inputs: [input.path], outputPath: output.path, emit: .apk,
                target: .hostDefault(), includeJVMRuntime: true, android: android
            )
            let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
            try #require(result.exitCode == 0, "\(result.diagnostics.map(\.message))")

            let link = try String(contentsOf: tools.appendingPathComponent("link-args.txt"), encoding: .utf8)
                .split(separator: "\n").map(String.init)
            #expect(link.contains("--auto-add-overlay"))
            #expect(link.contains("--debug-mode"))
            #expect(zip(link, link.dropFirst()).contains { $0 == ("--extra-packages", "lib.widget") })
            #expect(zip(link, link.dropFirst()).contains { $0 == ("--target-sdk-version", "34") })
            #expect(zip(link, link.dropFirst()).contains { $0 == ("--rename-manifest-package", "app.debug") })
            #expect(zip(link, link.dropFirst()).contains { $0.0 == "-R" && $0.1.hasSuffix("library-res-0.zip") })
            let merged = try String(contentsOf: tools.appendingPathComponent("merged.xml"), encoding: .utf8)
            #expect(merged.contains("package=\"app\""))
            #expect(merged.contains("android:name=\"lib.widget.WidgetProvider\""))
            #expect(merged.contains("android:authorities=\"app.debug.widget\""))

            let d8 = try String(contentsOf: tools.appendingPathComponent("d8-args.txt"), encoding: .utf8)
            // The AAR's classes.jar (unpacked to `aar-0/`) is a d8 program input.
            #expect(d8.split(separator: "\n").contains { $0.hasSuffix("/aar-0/classes.jar") })
            let apk = try ZipArchive(data: Data(contentsOf: output))
            let names = Set(apk.entries.map(\.name))
            #expect(names.contains("classes.dex"))
            #expect(names.contains("META-INF/services/lib.Service"))
            #expect(!names.contains("META-INF/LICENSE.txt"))
            #expect(!names.contains("META-INF/MANIFEST.MF"))
            // Stored, so `android:extractNativeLibs="false"` can map it in place.
            #expect(apk.entries.first { $0.name == "lib/arm64-v8a/libwidget.so" }?.compressionMethod == 0)
            #expect(fileManager.fileExists(atPath: root.appendingPathComponent("maven-cache/org/example/widget/1.0/widget-1.0.aar").path))
        }
    }

    /// `runFrontend` (analysis without codegen) also compiles Android Java
    /// sources, so it must install the runtime-jar provider the way the full
    /// pipeline does.
    @Test
    func frontendOnlyRunCompilesJavaSourcesAgainstTheRuntimeJar() throws {
        try withWorkspace { root in
            let tools = root.appendingPathComponent("build-tools/36.1.0", isDirectory: true)
            let platform = root.appendingPathComponent("platforms/android-36.1", isDirectory: true)
            for directory in [tools, platform] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try writeFakeAndroidJar(to: platform.appendingPathComponent("android.jar"), root: root)
            let d8 = tools.appendingPathComponent("d8")
            try "#!/bin/sh\nexit 0\n".write(to: d8, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d8.path)
            let bridge = root.appendingPathComponent("Bridge.java")
            try "package app; public final class Bridge { public static String mark() { return kotlin.Unit.INSTANCE.toString(); } }"
                .write(to: bridge, atomically: true, encoding: .utf8)
            let input = root.appendingPathComponent("Main.kt")
            try "package app\nfun mark(): String = Bridge.mark()\n".write(to: input, atomically: true, encoding: .utf8)
            AndroidBuildInputs.runtimeJarProvider = nil
            var android = AndroidOptions(sdkPath: root.path)
            android.javaSources = [bridge.path]
            let options = CompilerOptions(
                moduleName: "FrontendApp", inputs: [input.path], outputPath: root.appendingPathComponent("app.zip").path,
                emit: .dex, target: .hostDefault(), includeJVMRuntime: true, android: android
            )
            let result = CompilerDriver(backendPhases: makeBackendPhases).runFrontend(options: options)
            let errors = result.context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map(\.message))")
        }
    }

    @Test
    func apkJavaResourceFilterMatchesAGPDefaults() {
        for kept in ["META-INF/services/kotlinx.coroutines.CoroutineExceptionHandler",
                     "META-INF/androidx.core_core.version", "kotlin/kotlin.kotlin_builtins", "DebugProbesKt.bin"] {
            #expect(AndroidPackaging.isPackagedJavaResource(kept), "\(kept)")
        }
        for dropped in ["META-INF/MANIFEST.MF", "META-INF/LICENSE.txt", "META-INF/app.kotlin_module",
                        "META-INF/CERT.RSA", "META-INF/maven/g/a/pom.xml", "META-INF/versions/9/x.txt",
                        "LICENSE", "a/B.class", "../escape", "dir/.hidden"] {
            #expect(!AndroidPackaging.isPackagedJavaResource(dropped), "\(dropped)")
        }
    }
}
#endif
