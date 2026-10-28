@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendUserDefinedListTests {
    private let upstreamSource = """
    class List<T>(val head: T, val tail: List<T>? = null)
    fun <T> List<T>.mapHead(f: (T) -> T): List<T> = List<T>(f(head), null)
    fun box(): String {
        val a: Int = List<Int>(1).mapHead { it * 2 }.head
        return if (a == 2) "OK" else a.toString()
    }

    class Box<T>(val head: T)

    fun main() {
        println(box())
        println(List<Int>(7).head)
        println(Box<Int>(7).head)
        val standard: kotlin.collections.List<Int> = listOf(4, 5)
        println(standard.size)
    }
    """

    private let listValueControlSource = """
    class List<T>(val value: T)

    fun main() {
        println(List<Int>(7).value)
    }
    """

    /// KUU-3116: preserve the constructor owner for the upstream kt707 case.
    @Test(arguments: [(true, 0), (true, 2), (false, 0), (false, 2)])
    func testJetBrainsKt707(stdlibFromSource: Bool, optimization: Int) throws {
        try assertProgramOutput(
            upstreamSource,
            moduleName: "KUU3116JetBrainsKt707",
            expected: "OK\n7\n7\n2\n",
            stdlibFromSource: stdlibFromSource,
            optimization: optimization
        )
    }

    /// KUU-3116: a different primary property on a user-defined `List` still resolves.
    @Test(arguments: [(true, 0), (false, 0)])
    func testListValuePropertyControl(stdlibFromSource: Bool, optimization: Int) throws {
        try assertProgramOutput(
            listValueControlSource,
            moduleName: "KUU3116ListValueControl",
            expected: "7\n",
            stdlibFromSource: stdlibFromSource,
            optimization: optimization
        )
    }

    /// KUU-3116: resolving the constructor owner must not make absent members valid.
    @Test(arguments: [true, false])
    func testMissingUserDefinedListPropertyIsRejected(stdlibFromSource: Bool) throws {
        let artifactPath = stdlibFromSource
            ? nil
            : try StdlibArtifactRegressionTests.buildStdlibArtifact()
        let source = """
        class List<T>(val head: T)
        fun main() { print(List<Int>(7).missing) }
        """
        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: "KUU3116MissingListProperty",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                includeStdlib: stdlibFromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(result.exitCode != 0)
            #expect(result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
            #expect(!result.diagnostics.contains { $0.code == "KSWIFTK-KIR-0003" })
        }
    }

    private func assertProgramOutput(
        _ source: String,
        moduleName: String,
        expected: String,
        stdlibFromSource: Bool,
        optimization: Int
    ) throws {
        let artifactPath = stdlibFromSource
            ? nil
            : try StdlibArtifactRegressionTests.buildStdlibArtifact()
        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: stdlibFromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stdout == expected)
        }
    }
}
