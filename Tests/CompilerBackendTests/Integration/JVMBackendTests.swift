#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct JVMBackendTests {
    func withWorkspace(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jvm-m1-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func compile(_ source: String, root: URL, mode: EmitMode, flags: [String] = [], classpath: [String] = []) throws -> (Int, [Diagnostic]) {
        let input = root.appendingPathComponent("hello.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: "JVMTest", inputs: [input.path],
            outputPath: root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path,
            emit: mode, target: .hostDefault(), frontendFlags: flags, jvmClasspath: classpath
        )
        // Default options deliberately request stdlib, to catch accidental
        // Native artifact preparation or source injection in the JVM route.
        #expect(!options.includeStdlib)
        let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
        return (result.exitCode, result.diagnostics)
    }

    func java(_ arguments: [String]) throws -> CommandResult {
        let executable = CommandRunner.resolveExecutable("java", fallback: "/usr/bin/java")
        return try CommandRunner.run(executable: executable, arguments: ["-Xverify:all", "-Dfile.encoding=UTF-8"] + arguments, timeout: 20)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func helloWorldExecutesOnJVM(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("fun main() { println(\"Hello World\") }", root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let arguments = mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"]
            let execution = try java(arguments)
            #expect(execution.stdout == "Hello World\n")
            #expect(execution.stderr.isEmpty)
            if mode == .jvmClass {
                let data = try Data(contentsOf: root.appendingPathComponent("classes/HelloKt.class"))
                #expect(Array(data.prefix(8)) == [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 52])
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func packageUnicodeEscapesAndPrintOrder(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = #"""
            package demo.greeting
            fun main(): Unit {
                print("Hello, ")
                println("世界 😀\u0000\t\"\\")
                println()
                println("\uD83D\uDE00")
            }
            """#
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "demo.greeting.HelloKt"])
            #expect(execution.stdout == "Hello, 世界 😀\0\t\"\\\n\n😀\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: ["fun main() {}", "fun main() = println(\"expression\")"])
    func emptyAndExpressionBodies(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 0)
            let execution = try java(["-jar", root.appendingPathComponent("hello.jar").path])
            #expect(execution.stdout == (source.contains("expression") ? "expression\n" : ""))
        }
    }

    @Test
    func wideConstantIndicesAndDeterministicArchive() throws {
        try withWorkspace { root in
            let source = "fun main() {\n" + (0..<300).map { "println(\"line\($0)\")" }.joined(separator: "\n") + "\n}"
            #expect(try compile(source, root: root, mode: .jvmJar).0 == 0)
            let output = root.appendingPathComponent("hello.jar")
            let first = try Data(contentsOf: output)
            #expect(try compile(source, root: root, mode: .jvmJar).0 == 0)
            #expect(try Data(contentsOf: output) == first)
            let execution = try java(["-jar", output.path])
            #expect(execution.stdout == (0..<300).map { "line\($0)\n" }.joined())
        }
    }

    @Test(arguments: [
        "fun main(args: Array<String>) {}",
        "fun main(): Int = 1",
        "fun main() { unknown(\"wrong target\") }",
        "fun main() { print() }",
        "fun main() { println(missing = \"wrong argument\") }",
        "import other.println\nfun main() { println(\"wrong target\") }",
        "@Deprecated(\"ignored\") fun main() {}",
        "fun main() { @Missing println(\"ignored annotation\") }",
        "fun main() where T : Any { println(\"ignored constraint\") }",
        "fun main() { println(\"ignored trailing token\") garbage }",
        "fun main() = println(\"ignored trailing token\") garbage",
        "fun main() { label@ println(\"ignored label\") }",
    ])
    func rejectsUnsupportedProgramsWithoutWritingOutput(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.severity == .error })
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }

    @Test(arguments: [65_536, 8_000])
    func rejectsClassfileLimitsWithoutReplacingExistingOutput(size: Int) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar")
            let original = Data("previous output".utf8)
            try original.write(to: output)
            let body = size == 65_536
                ? "println(\"" + String(repeating: "a", count: size) + "\")"
                : String(repeating: "println(\"a\")\n", count: size)
            let result = try compile("fun main() {\n\(body)\n}", root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0002" })
            #expect(try Data(contentsOf: output) == original)
        }
    }

    @Test
    func rejectsIncrementalModeBeforeAccessingCache() throws {
        try withWorkspace { root in
            let result = try compile("fun main() {}", root: root, mode: .jvmJar, flags: ["incremental"])
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.severity == .error })
        }
    }
}
#endif
