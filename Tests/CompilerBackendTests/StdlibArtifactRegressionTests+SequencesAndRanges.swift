@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KUU-1301: chunked transforms escape into nested sequence/iterator objects.
    /// Exercise both source injection and imported stdlib callback ABIs.
    @Test(arguments: [false, true])
    func testSequenceChunkedTransformCaptures(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/sequence_chunked_transform_capture.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "SequenceChunkedTransformCaptures",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            [3, 7, 5]
            [[1, 2], [3, 4], [5]]
            [3, 7, 5]
            [103, 107, 105]
            [chunk:1+2, chunk:3+4, chunk:5]
            [[1, 2], [3, 4], [5]]
            []
            0
            [3]
            1
            [3, 7, 5]
            4
            transform
            size 0 must be greater than zero.

            """)
        }
    }

    /// A direct range expression can retain its primitive element type in
    /// Sema. Its source-backed members still receive a runtime range box,
    /// which has no Kotlin vtable.
    @Test
    func testLongRangeExpressionIteratorThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            val iterator = (Long.MAX_VALUE - 1L..Long.MAX_VALUE).iterator()
            while (iterator.hasNext()) println(iterator.next())
            println(iterator.hasNext())

            val range: LongRange = Long.MIN_VALUE..Long.MIN_VALUE
            val typedIterator: LongIterator = range.iterator()
            println(typedIterator.nextLong())
            println(typedIterator.hasNext())
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "LongRangeExpressionIteratorArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                9223372036854775806
                9223372036854775807
                false
                -9223372036854775808
                false

                """)
        }
    }

    /// STDLIB-ARTIFACT-010: `emptySequence()` must resolve to the source-backed
    /// stdlib factory (not a runtime `RuntimeSequenceBox`) so that `withIndex()`
    /// and other source-implemented `Sequence` extensions can call `source.iterator()`
    /// through normal virtual dispatch.
    @Test
    func testEmptySequenceWithIndexSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = try diffCaseSource("sequence_withindex.kt", file: #filePath)

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "[IndexedValue(index=0, value=10), IndexedValue(index=1, value=20), IndexedValue(index=2, value=30)]\n[IndexedValue(index=0, value=10)]\n[]\n")
        }
    }

    /// STDLIB-ARTIFACT-012: `Array.asSequence()` must lower to the runtime
    /// `kk_array_asSequence` bridge through the shared stdlib artifact so that
    /// downstream `Sequence.filterIsInstance`/`toList` operate on the array
    /// elements instead of silently producing an empty list.
    @Test
    func testArrayAsSequenceFilterIsInstanceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val values: Array<Any> = arrayOf(1, "two", 3)
            println(values.asSequence().filterIsInstance<Int>().toList())
            println(values.asSequence().filterIsInstance<String>().toList())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "[1, 3]\n[two]\n")
        }
    }

    /// STDLIB-ARTIFACT-017: source-implemented `Sequence` HOFs (`flatMap`,
    /// `flatMapIndexed`) dispatch `Sequence.iterator()` on runtime-backed
    /// collections (`List`) returned by their lambdas. Runtime-backed
    /// collection boxes must advertise the `Sequence` itable so the generated
    /// interface dispatch resolves even when the type checker picks the
    /// `Sequence` overload for an `Iterable`/`List` result. `String.lineSequence()`
    /// also relies on `RuntimeSequenceBox`/`RuntimeSequenceIteratorBox` itables.
    @Test
    func testSequenceFlatMapAndLineSequenceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println(sequenceOf(1, 2).flatMap { listOf(it, it * 10) }.toList())
            println(sequenceOf(1, 2).flatMapIndexed { index, value -> listOf(index, value * 10) }.toList())
            println("line1\nline2".lineSequence().toList())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "[1, 10, 2, 20]\n[0, 10, 1, 20]\n[line1, line2]\n")
        }
    }

    /// STDLIB-ARTIFACT-021: `Sequence<T>.reduce`'s bundled source body iterated
    /// its receiver with a direct `for (elem in this)` loop. Through the shared
    /// stdlib artifact, that loop silently ran zero times (the receiver's
    /// `Iterator` itable dispatch does not round-trip through the artifact),
    /// so `reduce` always threw "Empty sequence can't be reduced." even for a
    /// non-empty sequence. `fold`/`scan` were unaffected because their bodies
    /// materialize the receiver via `toList()` first. Rewrote `reduce` to do
    /// the same.
    @Test
    func testSequenceReduceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val seq = generateSequence(1) { if (it < 5) it + 1 else null }
            println(seq.reduce { acc, v -> acc + v })
            println(sequenceOf(1, 2, 3).reduce { acc, v -> acc + v })
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "15\n6\n")
        }
    }

    /// KSP-1022: an imported non-inline range iterator must not be redirected
    /// by InlineLoweringPass to the same-named MutableMap inline extension.
    /// The name fallback is only valid when the call has no known semantic
    /// symbol; artifact consumers otherwise lose the receiver-specific binding.
    @Test
    func testRangeHOFDoesNotUseSameNamedMutableMapIteratorFromArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println((1..5).reduce { acc, value -> acc + value })
            println((1..5).reduceIndexed { index, acc, value -> acc + index * value })
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KSP1022RangeArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "15\n41\n")
        }
    }

    /// `UIntProgression.fromClosedRange` / `downTo` / `step` lower to runtime
    /// factories, so the returned handle never passes `kk_object_new` and never
    /// received the constructor-site `kk_object_register_vtable_method`
    /// registrations. Once `UIntRange : UIntProgression` made the progression
    /// open, dispatch on its source-backed `toString`/`equals`/`hashCode` went
    /// through `kk_vtable_lookup` and trapped. The lowering now registers the
    /// nominal vtable implementations on range factory boxes, which also makes
    /// `UIntRange` overrides win when a range handle is viewed through the
    /// progression base type.
    @Test
    func testUIntProgressionOpenMembersDispatchOnFactoryBox() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            val positive = UIntProgression.fromClosedRange(2u, 11u, 3)
            val negative = 10u downTo 1u step 3
            println(positive)
            println(negative)
            val asProgression: UIntProgression = UIntRange(2u, 6u)
            println(asProgression)
            println(positive == UIntProgression.fromClosedRange(2u, 11u, 3))
            println(positive == negative)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "UIntProgressionFactoryVtable",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "2..11 step 3\n10 downTo 1 step 3\n2..6 step 1\ntrue\nfalse\n")
        }
    }
}
