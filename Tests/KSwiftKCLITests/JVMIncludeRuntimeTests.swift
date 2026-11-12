#if canImport(Testing)
import CompilerCore
import Foundation
@testable import KSwiftKCLI
import Testing

@Suite
struct JVMIncludeRuntimeTests {
    @Test
    func bundlesRuntimeAndPreservesApplicationMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-include-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("RuntimeMain.kt")
        try """
        package example
        fun main() {
            val after: () -> Unit = {}
            println(listOf("one", "two").reversed().joinToString("/"))
            after()
        }
        """.write(to: input, atomically: true, encoding: .utf8)

        let arguments = ["--emit", "jar", "-m", "KSwiftKStdlib", input.path]
        let plainJAR = root.appendingPathComponent("plain.jar")
        let runnableJAR = root.appendingPathComponent("runnable.jar")
        try #require(CLICompilerService.shared.run(args: arguments + ["-o", plainJAR.path]) == 0)
        try #require(CLICompilerService.shared.run(args: arguments + ["-include-runtime", "-o", runnableJAR.path]) == 0)

        let plain = try ZipArchive(data: Data(contentsOf: plainJAR))
        let runnable = try ZipArchive(data: Data(contentsOf: runnableJAR))
        let runnableNames = runnable.entries.map(\.name)
        #expect(Set(runnableNames).count == runnableNames.count)
        #expect(runnable.entry(named: "example/RuntimeMainKt.class") != nil)
        #expect(plain.entry(named: "kotlin/collections/CollectionsKt.class") == nil)
        #expect(runnable.entry(named: "kotlin/collections/CollectionsKt.class") != nil)
        #expect(runnable.entry(named: "kotlin/kotlin.kotlin_builtins") != nil)

        let plainUnit = try #require(plain.entry(named: "kotlin/Unit.class"))
        let runtimeUnit = try #require(runnable.entry(named: "kotlin/Unit.class"))
        #expect(try plain.contents(of: plainUnit) != runnable.contents(of: runtimeUnit))

        let plainManifest = try #require(plain.entry(named: "META-INF/MANIFEST.MF"))
        let runnableManifest = try #require(runnable.entry(named: "META-INF/MANIFEST.MF"))
        let manifest = try runnable.contents(of: runnableManifest)
        #expect(String(decoding: manifest, as: UTF8.self).contains("Main-Class: example.RuntimeMainKt\r\n"))
        #expect(try manifest == plain.contents(of: plainManifest))

        let plainModule = try #require(plain.entry(named: "META-INF/KSwiftKStdlib.kotlin_module"))
        let appModule = try #require(runnable.entry(named: "META-INF/KSwiftKStdlib.kotlin_module"))
        #expect(try runnable.contents(of: appModule) == plain.contents(of: plainModule))
        #expect(runnable.entry(named: "META-INF/KSwiftKStdlibRuntime.kotlin_module") != nil)

        let java = CommandRunner.resolveExecutable("java", fallback: "/usr/bin/java")
        let verification = ["-Xverify:all", "-jar"]
        let result = try CommandRunner.run(executable: java, arguments: verification + [runnableJAR.path], timeout: 20)
        #expect(result.stdout == "two/one\n")
        #expect(result.stderr.isEmpty)
        do {
            _ = try CommandRunner.run(executable: java, arguments: verification + [plainJAR.path], timeout: 20)
            Issue.record("Expected the plain JAR to require the Kotlin/JVM runtime on the classpath.")
        } catch CommandRunnerError.nonZeroExit(let failure) {
            #expect(failure.stderr.contains("NoClassDefFoundError: kotlin/collections/CollectionsKt"))
        }
    }

    @Test
    func unicodeAndAsciiClassNamesRunFromBundledJar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-unicode-class-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("UnicodeMain.kt")
        try """
        class 物(val n: Int)
        class Plain(val n: Int)
        fun main() {
            println(物(42).n)
            println(Plain(7).n)
        }
        """.write(to: input, atomically: true, encoding: .utf8)

        let runnableJAR = root.appendingPathComponent("unicode.jar")
        let arguments = ["--emit", "jar", "-m", "KSwiftKStdlib", input.path, "-include-runtime", "-o", runnableJAR.path]
        try #require(CLICompilerService.shared.run(args: arguments) == 0)

        let runnable = try ZipArchive(data: Data(contentsOf: runnableJAR))
        #expect(runnable.entry(named: "物.class") != nil)
        #expect(runnable.entry(named: "Plain.class") != nil)
        #expect(runnable.entry(named: "kotlin/Unit.class") != nil)

        let java = CommandRunner.resolveExecutable("java", fallback: "/usr/bin/java")
        let result = try CommandRunner.run(executable: java, arguments: ["-Xverify:all", "-jar", runnableJAR.path], timeout: 20)
        #expect(result.stdout == "42\n7\n")
        #expect(result.stderr.isEmpty)
    }

    @Test(arguments: ["executable", "class", "dex", "apk"])
    func requiresJarEmission(mode: String) {
        #expect(throws: CLIParseError.incompatibleStdlibOptions("-include-runtime requires --emit jar")) {
            try CLIParser.parse(args: ["-include-runtime", "--emit", mode, "main.kt"])
        }
    }
}
#endif
