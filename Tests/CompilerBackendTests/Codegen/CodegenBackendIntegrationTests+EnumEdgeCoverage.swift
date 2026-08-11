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

    /// BUG-178: `EnumEntries<T>` was registered as a completely empty
    /// synthetic interface (`HeaderHelpers+SyntheticEnumStubs.swift`'s
    /// `ensureEnumEntriesInterface`) with no `get` operator, so `entries[i]` /
    /// `enumEntries<T>()[i]` found no member candidate in Sema and the KIR
    /// indexed-access lowering (`CallLowerer+Operators.swift`) fell through to
    /// its generic built-in array-access path, which unconditionally emits
    /// `kk_array_get` — a `RuntimeArrayBox`-only intrinsic. `entries`'s actual
    /// runtime representation is a `RuntimeListBox` (`kk_enum_make_entries_list`
    /// in RuntimeEnum.swift), so this panicked with KSWIFTK-LINK-0003 at
    /// runtime. `values()`/`enumValues<T>()` (`Array<T>`/`RuntimeArrayBox`) and
    /// `for (d in entries)` (iterator-based, not indexed) were unaffected,
    /// which is what made this a narrower bug than "EnumEntries is broken".
    /// Fixed by registering a `get(index: Int): T` operator on `EnumEntries<T>`
    /// that reuses the same `__kk_list_get` bridge `List<E>.get` already uses
    /// (on top of `EnumEntries<T> : List<T>` from DEADCODE-014, which alone
    /// was not enough to make `[]` itself resolve). Complements
    /// `testCodegenEnumValuesEntriesElementAccessEqualityAndWhen` (BUG-177,
    /// which covers `Array.get`/forEach/for-in but not `EnumEntries.get`).
    @Test
    func testCodegenEnumEntriesIndexedAccessReturnsRealSingleton() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            println(Direction.entries[0])
            println(Direction.entries[3])
            println(enumEntries<Direction>()[1])
            println(Direction.entries[0] == Direction.NORTH)
            println(Direction.entries[1] == Direction.SOUTH)
            println(Direction.entries[0] == Direction.SOUTH)
            println(enumValues<Direction>()[2] == Direction.EAST)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEntriesIndexedAccess",
            expected:
                """
                NORTH
                WEST
                SOUTH
                true
                true
                false
                true
                """
                + "\n"
        )
    }

    /// BUG-177: `values()`/`entries` stored each element as a pre-baked name
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

    /// A reassigned enum-typed `var`'s `.name`/`.ordinal` access must reflect
    /// its current value at each read, not the value it held when first
    /// folded. `d.name`/`d.ordinal` used to be constant-folded against
    /// whichever entry happened to lower the local's *initializer*
    /// expression, because the local's KIR storage was aliased directly to
    /// that expression instead of getting its own copy — so any later
    /// reassignment updated the runtime bits but never changed what the
    /// fold saw, and it kept resolving to the entry the local started with.
    @Test
    func testEnumNameOrdinalReflectsReassignedVarValue() throws {
        let source = """
        enum class Direction { NORTH, SOUTH, EAST, WEST }

        fun main() {
            // if-without-else reassignment
            var d1: Direction = Direction.NORTH
            if (1 > 0) { d1 = Direction.SOUTH }
            println(d1.name)
            println(d1.ordinal)

            // if/else reassignment (both branches)
            var d2: Direction = Direction.NORTH
            if (1 > 0) { d2 = Direction.EAST } else { d2 = Direction.WEST }
            println(d2.name)
            println(d2.ordinal)

            // reassignment inside a loop, final value after last iteration
            var d3: Direction = Direction.NORTH
            for (i in 1..3) {
                d3 = if (i % 2 == 0) Direction.SOUTH else Direction.EAST
            }
            println(d3.name)
            println(d3.ordinal)

            // multiple sequential reassignments with no branching
            var d4: Direction = Direction.NORTH
            d4 = Direction.SOUTH
            d4 = Direction.EAST
            d4 = Direction.WEST
            println(d4.name)
            println(d4.ordinal)

            // while-loop reassignment
            var d5: Direction = Direction.NORTH
            var i = 0
            while (i < 2) {
                d5 = Direction.WEST
                i++
            }
            println(d5.name)
            println(d5.ordinal)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumNameOrdinalReassignedVar",
            expected:
                """
                SOUTH
                1
                EAST
                2
                EAST
                2
                WEST
                3
                WEST
                3
                """
                + "\n"
        )
    }
}
#endif
