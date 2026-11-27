#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func throwableMembersDelegateToJDK(mode: EmitMode) throws {
        let source = """
        fun main() {
            val exception = Exception("outer", Exception("inner"))
            println(exception.cause?.message)
            println(exception.stackTrace.size > 0)
            println(Exception("localized").localizedMessage)
            println(RuntimeException().localizedMessage)

            exception.addSuppressed(Exception("suppressed"))
            println(exception.suppressed.size)
            println(exception.suppressed[0].message)
            val suppressed = exception.getSuppressed()
            println(suppressed.size)
            println(suppressed[0].message)

            val initialized = Exception("initialized")
            println(initialized.initCause(Exception("init")) === initialized)
            println(initialized.cause?.message)

            try {
                throw Exception("printed")
            } catch (throwable: Exception) {
                throwable.printStackTrace()
            }
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let application = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", application.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "inner\ntrue\nlocalized\nnull\n1\nsuppressed\n1\nsuppressed\ntrue\ninit\n")
            let stderr = execution.stderr.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(stderr.hasPrefix("java.lang.Exception: printed\n\tat "))
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func localizedMessageUsesOverriddenJDKGetter(mode: EmitMode) throws {
        try withWorkspace { root in
            let javaClasses = root.appendingPathComponent("java-classes", isDirectory: true)
            try FileManager.default.createDirectory(at: javaClasses, withIntermediateDirectories: true)
            let javaSource = root.appendingPathComponent("LocalizedException.java")
            try """
            package dep;
            public final class LocalizedException extends RuntimeException {
                public LocalizedException(String message) { super(message); }
                @Override public String getLocalizedMessage() { return "localized"; }
            }
            """.write(to: javaSource, atomically: true, encoding: .utf8)
            let javaCompilation = try javac(["--release", "8", "-d", javaClasses.path, javaSource.path])
            #expect(javaCompilation.exitCode == 0, "\(javaCompilation.stderr)")

            let result = try compile("""
            import dep.LocalizedException
            fun Throwable.localizedLabel(): String? = localizedMessage
            fun main() {
                val exception = LocalizedException("ordinary")
                println(exception.message)
                println(exception.localizedMessage)
                println(exception.localizedLabel())
            }
            """, root: root, mode: mode, classpath: [javaClasses.path])
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let application = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", application.path + ":" + javaClasses.path, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "ordinary\nlocalized\nlocalized\n")
        }
    }

    @Test
    func localizedMessageImplicitReceiverCompilesInDexWithoutClasspath() throws {
        try withWorkspace { root in
            let tools = root.appendingPathComponent("build-tools/36.1.0", isDirectory: true)
            let platform = root.appendingPathComponent("platforms/android-36.1", isDirectory: true)
            for directory in [tools, platform] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try writeFakeAndroidJar(to: platform.appendingPathComponent("android.jar"), root: root)
            let d8 = tools.appendingPathComponent("d8")
            try """
            #!/bin/sh
            set -eu
            output=
            program_jar=
            while [ "$#" -gt 0 ]; do
                case "$1" in *.jar) program_jar=$1 ;; esac
                if [ "$1" = --output ]; then output=$2; shift; fi
                shift
            done
            printf '%s\n' "$program_jar" > "$(dirname "$0")/program-input-path.txt"
            cp "$program_jar" "$(dirname "$0")/program-input.jar"
            dex_dir="${output}.contents"
            mkdir -p "$dex_dir"
            printf 'test dex' > "$dex_dir/classes.dex"
            (cd "$dex_dir" && zip -q "$output" classes.dex)
            rm -rf "$dex_dir"
            """.write(to: d8, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d8.path)

            let input = root.appendingPathComponent("Main.kt")
            try """
            fun Throwable.label(): String? = localizedMessage
            fun main() { println(Exception("x").label()) }
            """.write(to: input, atomically: true, encoding: .utf8)
            let output = root.appendingPathComponent("app.dex")
            let options = CompilerOptions(
                moduleName: "LocalizedMessageDex", inputs: [input.path], outputPath: output.path,
                emit: .dex, target: .hostDefault(), android: AndroidOptions(sdkPath: root.path)
            )
            let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
            #expect(result.exitCode == 0, "\(result.diagnostics.map(\.message))")
            #expect(FileManager.default.fileExists(atPath: output.path))
            let dex = try ZipArchive(data: Data(contentsOf: output))
            #expect(dex.entries.contains { $0.name == "classes.dex" })
            let originalProgramJar = try String(contentsOf: tools.appendingPathComponent("program-input-path.txt"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(originalProgramJar.hasSuffix("classes.jar"))
            let programJar = tools.appendingPathComponent("program-input.jar").path
            let programArchive = try ZipArchive(data: Data(contentsOf: URL(fileURLWithPath: programJar)))
            let programClasses = programArchive.entries.compactMap { entry -> String? in
                guard entry.name.hasSuffix(".class") else { return nil }
                return entry.name.dropLast(6).replacingOccurrences(of: "/", with: ".")
            }
            #expect(!programClasses.isEmpty)
            let bytecode = try javap(["-c", "-p", "-classpath", programJar] + programClasses)
            #expect(bytecode.exitCode == 0, "\(bytecode.stderr)")
            #expect(bytecode.stdout.contains("getLocalizedMessage:()Ljava/lang/String;"), "\(bytecode.stdout)")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func throwableSuppressedCallableReferencesMatchRuntimeParity(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            import kotlin.reflect.KClass
            fun main() {
                val exception = RuntimeException("x")
                exception.addSuppressed(IllegalArgumentException("s"))
                val bound: () -> Array<Throwable> = exception::getSuppressed
                println(bound().size)
                println(bound()[0].message)
                val reflected = Throwable::getSuppressed
                val unbound: (Throwable) -> Array<Throwable> = reflected
                println(unbound(exception).size)
                println(unbound(exception)[0].message)
                println((reflected.returnType.classifier as KClass<*>).simpleName)
                println(reflected.returnType.arguments.size)
                println((reflected.returnType.arguments[0].type?.classifier as KClass<*>).simpleName)
                println(reflected.returnType.isMarkedNullable)
            }
            """, expected: "1\ns\n1\ns\nArray\n1\nThrowable\nfalse\n", mode: mode, root: root)
        }
    }
}
#endif
