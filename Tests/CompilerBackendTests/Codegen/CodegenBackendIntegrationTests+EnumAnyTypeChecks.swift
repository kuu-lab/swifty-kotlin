#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-182: an enum constant widened to `Any` was boxed as a raw ordinal Int
/// (or, after BUG-177, as a RuntimeIntBox with only a display name). Because
/// the box carried no stable nominal type ID and the enum class had no runtime
/// supertype edges, `is`/`as`/`as?`/`!is`/`KClass.isInstance` against the
/// enum class (or `kotlin.Enum`/`kotlin.Comparable`) failed or panicked.
///
/// Fixed by passing the stable nominal type ID to `kk_enum_box_ordinal` and
/// by having `__enum_static_init_*` register the enum class's supertype edges
/// (`kotlin.Enum` and `kotlin.Comparable`) so the runtime assignability walk
/// can answer checks correctly.

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
struct CodegenBackendEnumAnyTypeChecksTests {

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
    func testCodegenEnumWidenedToAnyAnswersTypeChecks() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            val boxed: Any = Direction.WEST
            println(boxed is Direction)
            println(boxed is Enum<*>)
            println(boxed is Comparable<*>)
            println(boxed !is Direction)
            println(boxed as Direction)
            println(boxed as? Direction)
            println(Direction::class.isInstance(boxed))

            val other: Any = 42
            println(other is Direction)
            println(other as? Direction)
            println(Direction::class.isInstance(other))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyTypeChecksMinimal",
            expected:
                """
                true
                true
                true
                false
                WEST
                WEST
                true
                false
                null
                false
                """
                + "\n"
        )
    }

    @Test
    func testCodegenMixedEnumClassesInAnyCollectionFilterCorrectly() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        enum class Color { RED, GREEN }

        fun main() {
            val mixed: List<Any> = listOf(Direction.NORTH, Color.RED, Direction.SOUTH, Color.GREEN)
            println(mixed.filterIsInstance<Direction>())
            println(mixed.filterIsInstance<Color>())
            println(mixed.filterIsInstance<Enum<*>>().size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumAnyFilterIsInstance",
            expected:
                """
                [NORTH, SOUTH]
                [RED, GREEN]
                4
                """
                + "\n"
        )
    }
}
#endif
