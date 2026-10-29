import Foundation
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct EnumBaseStringificationTests {
    @Test(arguments: [false, true], [0, 2])
    func implicitConversions(fromSource: Bool, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("Scripts/diff_cases/enum_base_stringification.kt")
        try compileAndRun(
            source: String(contentsOf: fixture, encoding: .utf8),
            expected: String(contentsOf: fixture.deletingPathExtension().appendingPathExtension("expected"), encoding: .utf8),
            fromSource: fromSource, optimization: optimization
        )
    }

    @Test(arguments: [0, 2])
    func libraryProducerOwnsDispatch(optimization: Int) throws {
        for visibility in ["private ", ""] {
            try compileAndRun(
                source: """
                import enumapi.*
                fun main() {
                    val value = exposed()
                    println(callCount())
                    println(value)
                    println("$value")
                    println(value.toString())
                    val erased: Any = value
                    println(erased)
                    println(callCount())
                    println(other())
                    \(visibility.isEmpty ? "val direct: Enum<*> = E.A; println(callCount()); println(direct)" : "")
                }
                """,
                expected: "0\ndisplay-1\ndisplay-2\ndisplay-3\ndisplay-4\n4\nbase-5\n"
                    + (visibility.isEmpty ? "5\ndisplay-6\n" : ""),
                producer: """
                package enumapi
                private var calls = 0
                \(visibility)enum class E {
                    A { override fun toString(): String { calls += 1; return "display-$calls" } },
                    B;
                    override fun toString(): String { calls += 1; return "base-$calls" }
                }
                fun exposed(): Enum<*> = E.A
                fun other(): Enum<*> = E.B
                fun callCount(): Int = calls
                """,
                fromSource: false, optimization: optimization
            )
        }
    }

    @Test(arguments: [0, 2])
    func privateEnumWithoutTopLevelProperties(optimization: Int) throws {
        try compileAndRun(
            source: "import enumapi.*\nfun main() { println(exposed()) }",
            expected: "second\n",
            producer: """
            package enumapi
            private enum class E {
                A { override fun toString(): String = "first" },
                B { override fun toString(): String = "second" }
            }
            fun exposed(): Enum<*> = E.B
            """,
            fromSource: false, optimization: optimization
        )
    }

    private func compileAndRun(
        source: String, expected: String, producer: String? = nil,
        fromSource: Bool, optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        var searchPaths: [String] = []
        if let producer {
            let input = directory.appendingPathComponent("producer.kt").path
            let output = directory.appendingPathComponent("EnumAPI").path
            try producer.write(toFile: input, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "EnumAPI", inputs: [input], outputPath: output, emit: .library,
                target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            )))
            searchPaths = [output + ".kklib"]
        }
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "EnumConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: searchPaths, target: defaultTargetTriple(), optLevel: level,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expected)
        #expect(result.stderr.isEmpty)
    }
}
