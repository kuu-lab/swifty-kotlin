#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-178: indexing an `EnumEntries<T>` (`Direction.entries[0]`,
/// `enumEntries<Direction>()[0]`) crashed at runtime with
/// `KSwiftK panic [KSWIFTK-LINK-0003]: Unhandled top-level exception`.
/// `entries` is backed by a `RuntimeListBox` (`kk_enum_make_entries_list`),
/// but `EnumEntries<T>` was registered as a member-less synthetic interface
/// with no `kotlin.collections.List<T>` supertype, so `[]` never found
/// `List.get` and fell back to the array bridge `kk_array_get`, which read
/// the list handle as a `RuntimeArrayBox` and threw. Registering the
/// supertype (`ensureEnumEntriesInterface`) routes `[]` to `__kk_list_get`;
/// `Array<T>`-typed `values()`/`enumValues<T>()` indexing keeps using
/// `kk_array_get` and is pinned here too.
@Suite
struct CodegenBackendEnumEntriesIndexAccessTests {

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenEnumEntriesIndexAccessMinimalRepro() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun main() {
            println(enumEntries<Direction>()[0])
        }
        """

        try assertKotlinOutput(source, moduleName: "EnumEntriesIndexMinimalRepro", expected: "NORTH\n")
    }

    @Test
    func testCodegenEnumEntriesIndexAccessAcrossReceiverShapes() throws {
        let source = """
        import kotlin.enums.EnumEntries

        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            println(Direction.entries[1])
            println(Direction.entries.get(2))
            val entries: EnumEntries<Direction> = Direction.entries
            for (i in entries.indices) {
                println(entries[i])
            }
            println(entries[0] == Direction.NORTH)
            println(enumValues<Direction>()[2] == Direction.entries[2])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntriesIndexReceiverShapes",
            expected: """
            SOUTH
            EAST
            NORTH
            SOUTH
            EAST
            WEST
            true
            true

            """
        )
    }
}
#endif
