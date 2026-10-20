#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExpectActualEnumExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func enumToStringLinksAcrossConsumerImports(fromSource: Bool, optimization: Int) throws {
        let consumers = [
            "import x.E\nfun main(){println(E.A.toString())}",
            "import x.E.A\nfun main(){println(A.toString())}",
        ]
        for consumer in consumers {
            try compileAndRun(
                common: "package x\nexpect enum class E { A }",
                platform: "package x\nactual enum class E { A }",
                consumer: consumer,
                expected: "A\n",
                fromSource: fromSource,
                optimization: optimization
            )
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func enumToStringLinksAcrossWildcardImport(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(
            common: "package x\nexpect enum class E { A }",
            platform: "package x\nactual enum class E { A }",
            consumer: "import x.E.*\nfun main(){println(A.toString())}",
            expected: "A\n",
            fromSource: fromSource,
            optimization: optimization
        )
    }

    @Test func pairedEnumEntriesKeepDistinctIdentityAndNames() throws {
        try compileAndRun(
            common: "package x\nexpect enum class E { A, B }",
            platform: "package x\nactual enum class E { A, B }",
            consumer: """
            import x.E
            enum class P { A, B }
            fun main() {
                println(E.A === E.B)
                println(E.A != E.B)
                println(E.A.name)
                println(E.B.name)
                println(E.values().size)
                println(E.entries.size)
                println(E.valueOf("B").name)
                println(P.A === P.B)
            }
            """,
            expected: "false\ntrue\nA\nB\n2\n2\nB\nfalse\n",
            fromSource: false,
            optimization: 0
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func actualEntriesKeepTheirNamesAndOrdinals(fromSource: Bool, optimization: Int) throws {
        try compileAndRun(
            common: "package x\nexpect enum class E { A, B }",
            platform: "package x\nactual enum class E { A, B, C }",
            consumer: """
            import x.E
            fun main() {
                println(E.A.toString())
                println(E.B.toString())
                println(E.C.toString())
                println(E.B.name)
                println(E.B.ordinal)
                println(E.values().size)
                println(E.entries.size)
                println(E.valueOf("C").toString())
            }
            """,
            expected: "A\nB\nC\nB\n1\n3\n3\nC\n",
            fromSource: fromSource,
            optimization: optimization
        )
    }

    private func compileAndRun(
        common: String,
        platform: String,
        consumer: String,
        expected: String,
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try withTemporaryFiles(contents: [common, platform, consumer]) { inputs in
            let output = directory.appendingPathComponent("enum-consumer").path
            let options = CompilerOptions(
                moduleName: "ExpectActualEnum",
                inputs: inputs,
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "expect/actual enum consumer: \(consumer)"
            )
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution failed: \(result.stderr)")
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
