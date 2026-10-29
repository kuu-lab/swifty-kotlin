import Foundation
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct RangeClassLiteralArtifactTests {
    private func expectedOutput(_ fixture: String) throws -> String {
        try diffCaseSource(fixture.replacingOccurrences(of: ".kt", with: ".expected"))
    }

    private func run(_ output: String, expected: String) throws {
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == expected)
    }

    private func scenarios(fromSource: Bool) throws -> [(name: String, source: String, expected: String)] {
        let matrix = "bound_range_class_identity.kt"
        let indices = "kotlinx_io_bytestring_indices_class.kt"
        if fromSource {
            // Inject the full stdlib once per optimization level. Keep the exact
            // minimal function/call, first lookup, matrix, and indices assertions.
            let classSource = try diffCaseSource(matrix)
            let indicesSource = try diffCaseSource(indices)
            let indicesStart = try #require(indicesSource.range(of: "fun main() {"))
            let indicesEnd = try #require(indicesSource.range(of: "}", options: .backwards))
            let classEnd = try #require(classSource.range(of: "}", options: .backwards))
            let imports = "import kotlinx.io.bytestring.ByteString\nimport kotlinx.io.bytestring.indices\n"
            let source = imports + classSource[..<classEnd.lowerBound]
                + indicesSource[indicesStart.upperBound..<indicesEnd.lowerBound] + "}\n"
            return [("bound_range_and_indices_class.kt", source,
                     try expectedOutput(matrix) + expectedOutput(indices))]
        }
        return try ["bound_int_range_class_literal.kt", matrix, indices].map {
            ($0, try diffCaseSource($0), try expectedOutput($0))
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func minimalAndIdentityMatrix(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        for scenario in try scenarios(fromSource: fromSource) {
            let input = directory.appendingPathComponent(scenario.name).path
            let output = input + ".out"
            try scenario.source.write(toFile: input, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "RangeClassLiteral", inputs: [input], outputPath: output,
                emit: .executable, target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: !fromSource
            )))
            try run(output, expected: scenario.expected)
        }
    }

    @Test(arguments: [0, 2])
    func producerConsumerPreservesRangeClassifier(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = try testStdlibArtifactPath()
        let api = directory.appendingPathComponent("api.kt").path
        let library = directory.appendingPathComponent("RangeAPI").path
        try """
        package range.api
        import kotlin.reflect.KClass
        fun name(value: Any): String? = value::class.simpleName
        fun classifier(value: Any): KClass<*> = value::class
        fun erased(): Any = 1..2
        fun literal(): KClass<*> = IntRange::class
        """.write(toFile: api, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "RangeAPI", inputs: [api], outputPath: library, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
        )))
        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try """
        import range.api.*
        fun main() {
            println(name(1..2))
            val actual = classifier(erased())
            println(actual.simpleName)
            println(actual.qualifiedName)
            println(actual == IntRange::class)
            println(actual === IntRange::class)
            println(actual === literal())
            println(actual.isInstance(1..2))
            println(actual.isInstance(1L..2L))
            println((1..2)::class === literal())
        }
        """.write(toFile: input, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "RangeConsumer", inputs: [input], outputPath: output, emit: .executable,
            searchPaths: [library + ".kklib"], target: defaultTargetTriple(),
            optLevel: level, stdlibLibraryPath: stdlib
        )))
        let expected = "IntRange\nIntRange\nkotlin.ranges.IntRange\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\n"
        // Execute twice in separate processes to catch dependence on a prior registry/cache.
        try run(output, expected: expected)
        try run(output, expected: expected)
    }
}
