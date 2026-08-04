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
struct CodegenBackendEnumEdgeCoverageTests {

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

    @Test
    func testCodegenCompilesEnumEdgeCoverage() throws {
        let source = """
        enum class Direction {
            NORTH,
            SOUTH,
        }

        fun main() {
            println(Direction.entries)
            println(enumValues<Direction>().toList())
            println(enumValueOf<Direction>("NORTH"))
            println(Direction.SOUTH.name)
            println(Direction.SOUTH.ordinal)

            try {
                println(enumValueOf<Direction>("WEST"))
            } catch (e: Throwable) {
                println("invalid-enum-name")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEdgeCoverage",
            expected:
                """
                [NORTH, SOUTH]
                [NORTH, SOUTH]
                NORTH
                SOUTH
                1
                invalid-enum-name
                """
                + "\n"
        )
    }

    /// BUG-172: `values()`/`entries` stored each element as a pre-baked name
    /// string instead of a genuinely boxed ordinal (see
    /// `appendEnumOrdinalArrayCreation` /
    /// `CallLowerer+EnumStdlib.lowerEnumEntryCollectionCallExpr`). Printing an
    /// *individual* element read out of the collection unboxed that string as
    /// an Int (garbage, matching no ordinal) and printed a blank line;
    /// comparing it against a real enum constant compared an unrelated boxed
    /// handle against a raw ordinal and was always false. Printing the whole
    /// collection happened to look right regardless, since the elements were
    /// already name strings -- this test pins that this remains true now
    /// that elements are real boxed ordinals tagged with their name (see
    /// `kk_enum_box_ordinal` / `RuntimeIntBox.enumEntryName`).
    @Test
    func testCodegenEnumValuesEntriesElementAccessEqualityAndWhen() throws {
        let source = """
        enum class Direction {
            NORTH,
            SOUTH,
        }

        fun main() {
            enumValues<Direction>().forEach { d -> println(d) }
            for (d in Direction.entries) {
                println(d)
            }
            println(enumValues<Direction>().toList())
            println(Direction.entries)

            val first = enumValues<Direction>()[0]
            val second = enumValues<Direction>()[1]
            println(first == Direction.NORTH)
            println(first == Direction.SOUTH)
            println(second == Direction.SOUTH)
            when (first) {
                Direction.NORTH -> println("first-is-north")
                Direction.SOUTH -> println("first-is-south")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumValuesEntriesElementAccess",
            expected:
                """
                NORTH
                SOUTH
                NORTH
                SOUTH
                [NORTH, SOUTH]
                [NORTH, SOUTH]
                true
                false
                true
                first-is-north
                """
                + "\n"
        )
    }
}
#endif
