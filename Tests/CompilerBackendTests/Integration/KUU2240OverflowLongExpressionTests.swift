#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

@Suite(.serialized)
struct KUU2240OverflowLongExpressionTests {
    private static let source = #"""
    // Pinned JetBrains Kotlin testData: compiler/testData/codegen/box/binaryOp/overflowLong.kt
    // commit: 679366a83f99851b42f64795f10ed803ff011c73
    fun box(): String {
        val a: Long = 2147483647 + 1
        if (a != -2147483648L) return "fail: in this case we should add to ints and than cast the result to long - overflow expected"

        val l1 = Long.MAX_VALUE
        val l2 = l1 + 1
        if (l2 > l1) return "fail: Long.MAX_VALUE + 1 should overflow to negative."

        val l3 = Long.MIN_VALUE
        val l4 = l3 - 1
        if (l4 < l3) return "fail: Long.MIN_VALUE - 1 should overflow to positive."

        return "OK"
    }

    fun value(): Long = 2147483647 + 1

    fun main() {
        println(box())
        println(value())
        val direct: Long = 1
        val typed: Long = 2147483647L + 1L
        println(direct)
        println(typed)
    }
    """#

    private func assertPublicOriginalAndMinimalRun(
        optimization: OptimizationLevel
    ) throws {
        TestStdlibCache.shared.prepare()
        let artifactPath = try testStdlibArtifactPath()

        try withTemporaryFile(contents: Self.source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "KUU2240OverflowLong",
                outputPath: outputPath,
                optLevel: optimization,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            let lane = "fresh stdlib artifact, \(optimization)"
            #expect(result.exitCode == 0, "\(lane): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(lane): \(result.stderr)")
            #expect(
                result.stdout == "OK\n-2147483648\n1\n2147483648\n",
                Comment(rawValue: lane)
            )
        }
    }

    @Test
    func freshStdlibArtifactO0() throws {
        try assertPublicOriginalAndMinimalRun(optimization: .O0)
    }

    @Test
    func freshStdlibArtifactO2() throws {
        try assertPublicOriginalAndMinimalRun(optimization: .O2)
    }
}
#endif
