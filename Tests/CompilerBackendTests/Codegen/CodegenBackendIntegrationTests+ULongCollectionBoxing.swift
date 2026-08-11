#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

@Suite
struct CodegenBackendULongCollectionBoxingTests {

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    /// Regression for a ULong boxed into a generic collection (List/Set/Map):
    /// boxing previously reused kk_box_long / RuntimeLongBox, so any ULong
    /// value above Int64.max was reinterpreted as a negative signed Long
    /// wherever it went through boxed-Any dispatch (toString, equals,
    /// contains, sorted). RuntimeULongBox now keeps ULong distinguishable
    /// from Long at every one of those dispatch points.
    @Test
    func testULongBoxedInCollectionsRendersAndComparesAsUnsigned() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            val small: ULong = 5uL

            println(listOf(big, small))
            println(setOf(big, small))
            println(mapOf("big" to big, "small" to small))

            val list = listOf(big, small)
            println(list.contains(big))
            println(list.contains(6uL))
            println(list == listOf(big, small))

            println(listOf(small, big).sorted())
            println(listOf(big, small).sorted())

            val dedup = setOf(big, big, small)
            println(dedup.size)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ULongCollectionBoxing",
            expected:
                """
                [17663719463477156090, 5]
                [17663719463477156090, 5]
                {big=17663719463477156090, small=5}
                true
                false
                true
                [5, 17663719463477156090]
                [5, 17663719463477156090]
                2
                """
                + "\n"
        )
    }

    /// Regression: runtimeNullSentinelInt is Int64.min, which is also the raw
    /// bit pattern of ULong(2^63) and Long.MIN_VALUE. kk_box_ulong / kk_box_long
    /// used to short-circuit on that bit pattern and return it unboxed, so this
    /// one ordinary value got silently treated as null by every boxed-Any
    /// dispatch site (toString, equality, `is`). Verifies both the non-nullable
    /// boxing path and null still propagating correctly through nullable ULong?/
    /// Long? — including as a generic Any? function argument, which is a
    /// different lowering path than a plain `val x: Any? = ...` assignment.
    @Test
    func testULongAndLongBoxingAtNullSentinelBoundary() throws {
        let source = """
        fun show(x: Any?) {
            println(x)
        }

        fun main() {
            val big: ULong = 9223372036854775808uL
            val any: Any = big
            println(any)

            val nullU: ULong? = null
            val anyNull: Any? = nullU
            println(anyNull)
            show(nullU)

            val presentU: ULong? = 9223372036854775808uL
            val anyPresent: Any? = presentU
            println(anyPresent)
            show(presentU)

            val bigL: Long = Long.MIN_VALUE
            val anyL: Any = bigL
            println(anyL)

            val nullL: Long? = null
            show(nullL)

            val presentL: Long? = Long.MIN_VALUE
            show(presentL)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ULongLongNullSentinelBoundary",
            expected:
                """
                9223372036854775808
                null
                null
                9223372036854775808
                9223372036854775808
                -9223372036854775808
                null
                -9223372036854775808
                """
                + "\n"
        )
    }
}
#endif
