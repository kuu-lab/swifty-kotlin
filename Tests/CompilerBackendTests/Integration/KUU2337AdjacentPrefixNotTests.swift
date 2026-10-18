#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

@Suite(.serialized)
struct KUU2337AdjacentPrefixNotTests {
    private static let source = #"""
    // Pinned JetBrains Kotlin testData plus the KUU-2337 minimal reproduction.
    fun Long.id() = this

    fun String.drop2() = if (length >= 2) subSequence(2, length) else null

    fun String.anyLength(): Any = length
    fun doSimple(s: String?) = s?.length == 3

    fun doLongReceiver(x: Long) = x?.id() == 3L

    fun doChain(s: String?) = s?.drop2()?.length == 1

    fun doIf(s: String?) =

    if (s?.length == 1) "A" else "B"

    fun doCmpWithAny(s: String?) =

    s?.anyLength() == 3

    fun doIfNot(s: String?) =

    if (!(s?.length == 1)) "A" else "B"

    fun doIfNotNot(s: String?) =

    if (!!(s?.length == 1)) "A" else "B"

    fun box(): String = when {

    doSimple(null) -> "failed 1"

    doSimple("1") -> "failed 2"

    !doSimple("123") -> "failed 3"
    doLongReceiver(2L) -> "failed 4"

    !doLongReceiver(3L) -> "failed 5"

    doChain(null) -> "failed 6"

    doChain("1") -> "failed 7"

    !doChain("123") -> "failed 7"

    doIf("1") != "A" -> "failed 8"

    doIf("123") != "B" -> "failed 9"

    doIf(null) != "B" -> "failed 10"

    doCmpWithAny(null) -> "failed 11"

    doCmpWithAny("1") -> "failed 12"

    !doCmpWithAny("123") -> "failed 13"

    doIfNot("1") != "B" -> "failed 8"

    doIfNot("123") != "A" -> "failed 9"

    doIfNot(null) != "A" -> "failed 10"

    doIfNotNot("1") != "A" -> "failed 8"
    doIfNotNot("123") != "B" -> "failed 9"

    doIfNotNot(null) != "B" -> "failed 10"

    else -> "OK"

    }

    fun boxMin(): String = if (!!true) "OK" else "FAIL"
    fun boxNested(): String = if (!(!true)) "OK" else "FAIL"
    fun boxSpaced(): String = if (! !true) "OK" else "FAIL"
    fun boxSingle(): String = if (!false) "OK" else "FAIL"
    fun postfixNullAssertion(value: String?): String = value!!

    fun main() {
        println(box())
        println(boxMin())
        println(boxNested())
        println(boxSpaced())
        println(boxSingle())
        println(postfixNullAssertion("OK"))
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
                moduleName: "KUU2337AdjacentPrefixNot",
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
                result.stdout == "OK\nOK\nOK\nOK\nOK\nOK\n",
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
