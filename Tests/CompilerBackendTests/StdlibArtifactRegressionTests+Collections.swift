@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    private static func abstractCollectionSource() throws -> String {
        try diffCaseSource("bug_200_precompiled_abstract_collection.kt", file: #filePath)
    }

    /// KSP-697: inferred mutable collection factories must preserve their
    /// MutableIterable supertype when the stdlib is consumed as an artifact.
    @Test
    func testMutableFactoriesWidenThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        try withTemporaryFile(contents: """
        fun main() {
            val list = mutableListOf(1, 2, 3)
            val listIterable: MutableIterable<Int> = list
            val set = mutableSetOf(1, 2, 3)
            val setIterable: MutableIterable<Int> = set
        }
        """) { userPath in
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "MutableCollectionFactoryArtifact",
                emit: .kirDump,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Mutable collection factories should widen through MutableIterable: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    /// RF-GOLDEN-004: source-backed collection flags must not change the
    /// iterator route after the stdlib is serialized and imported. A concrete
    /// A concrete List receiver keeps the list bridge, while Iterable/MutableList
    /// interface receivers keep generic iterator operations so user overrides
    /// remain possible. The final output checks that both routes still execute
    /// correctly through the artifact.
    @Test
    func testCollectionForLoopIteratorRoutesThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun sumList(values: List<Int>): Int {
            var sum = 0
            for (value in values) { sum += value }
            return sum
        }

        fun sumIterable(values: Iterable<Int>): Int {
            var sum = 0
            for (value in values) { sum += value }
            return sum
        }

        fun sumMutableList(values: MutableList<Int>): Int {
            var sum = 0
            for (value in values) { sum += value }
            return sum
        }

        fun main() {
            val list = listOf(1, 2, 3)
            println(sumList(list))
            println(sumIterable(list))
            println(sumMutableList(mutableListOf(4, 5, 6)))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "CollectionForLoopIteratorArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)

            let listCallees = extractCallees(
                from: try findKIRFunctionBody(named: "sumList", in: module, interner: ctx.interner),
                interner: ctx.interner
            )
            #expect(listCallees.contains(try runtimeABICallee("list_iterator")), "artifact List loop must use kk_list_iterator: \(listCallees)")
            #expect(listCallees.contains(try runtimeABICallee("list_iterator_hasNext")), "artifact List loop must use list hasNext: \(listCallees)")
            #expect(listCallees.contains(try runtimeABICallee("list_iterator_next")), "artifact List loop must use list next: \(listCallees)")
            #expect(!listCallees.contains(try runtimeABICallee("iterable_iterator")), "artifact List loop must not use generic Iterable iterator: \(listCallees)")
            #expect(!listCallees.contains(try runtimeABICallee("iterator_hasNext")), "artifact List loop must not use generic hasNext: \(listCallees)")
            #expect(!listCallees.contains(try runtimeABICallee("iterator_next")), "artifact List loop must not use generic next: \(listCallees)")

            let iterableCallees = extractCallees(
                from: try findKIRFunctionBody(named: "sumIterable", in: module, interner: ctx.interner),
                interner: ctx.interner
            )
            #expect(iterableCallees.contains(try runtimeABICallee("iterable_iterator")), "artifact Iterable loop must use generic iterator: \(iterableCallees)")
            #expect(iterableCallees.contains(try runtimeABICallee("iterator_hasNext")), "artifact Iterable loop must use generic hasNext: \(iterableCallees)")
            #expect(iterableCallees.contains(try runtimeABICallee("iterator_next")), "artifact Iterable loop must use generic next: \(iterableCallees)")
            #expect(!iterableCallees.contains(try runtimeABICallee("list_iterator_hasNext")), "artifact Iterable loop must not use list hasNext: \(iterableCallees)")
            #expect(!iterableCallees.contains(try runtimeABICallee("list_iterator_next")), "artifact Iterable loop must not use list next: \(iterableCallees)")

            let mutableListCallees = extractCallees(
                from: try findKIRFunctionBody(named: "sumMutableList", in: module, interner: ctx.interner),
                interner: ctx.interner
            )
            #expect(mutableListCallees.contains(try runtimeABICallee("list_iterator")), "artifact MutableList loop must use the concrete list iterator: \(mutableListCallees)")
            #expect(mutableListCallees.contains(try runtimeABICallee("list_iterator_hasNext")), "artifact MutableList loop must use list hasNext: \(mutableListCallees)")
            #expect(mutableListCallees.contains(try runtimeABICallee("list_iterator_next")), "artifact MutableList loop must use list next: \(mutableListCallees)")
            #expect(!mutableListCallees.contains(try runtimeABICallee("iterable_iterator")), "artifact MutableList loop must not use generic Iterable iterator: \(mutableListCallees)")
            #expect(!mutableListCallees.contains(try runtimeABICallee("iterator_hasNext")), "artifact MutableList loop must not use generic hasNext: \(mutableListCallees)")
            #expect(!mutableListCallees.contains(try runtimeABICallee("iterator_next")), "artifact MutableList loop must not use generic next: \(mutableListCallees)")
            #expect(!mutableListCallees.contains(try runtimeABICallee("range_iterator")), "artifact MutableList loop must not use the range iterator: \(mutableListCallees)")

            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "6\n6\n15\n")
        }
    }

    /// BUG-200: bundled source and precompiled stdlib metadata must agree on
    /// abstract member modality and on the owner's type argument in overrides.
    @Test
    func testAbstractCollectionOverrideThroughBundledSource() throws {
        let source = try Self.abstractCollectionSource()
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "Bug200Source",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: true
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "0\n")
        }
    }

    /// BUG-200: the same source must compile and run when AbstractCollection
    /// and its members come from a stdlib library artifact.
    @Test
    func testAbstractCollectionOverrideThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try Self.abstractCollectionSource()
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "Bug200Artifact",
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
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "0\n")
        }
    }

    /// STDLIB-ARTIFACT-004: generic `maxOf`/`minOf` overloads on `Comparable`
    /// work through the shared stdlib artifact even though their `Comparable<T>`
    /// upper bound is not preserved in metadata; the CallLowerer recognizes the
    /// uniform type-parameter signature and lowers the comparison inline.
    @Test
    func testMaxOfComparableThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println(maxOf("banana", "apple"))
            println(maxOf("cherry", "apple", "banana"))
            println(maxOf("date", "banana", "apple", "cherry"))
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
            #expect(normalizedStdout == "banana\ncherry\ndate\n")
        }
    }

    /// STDLIB-ARTIFACT-013: imported inline-KIR bodies must preserve floating-point
    /// and character literals. `sumByDouble` uses `double:0.0` as its loop
    /// accumulator; if `LibraryInlineImport` drops `double:` tokens the accumulator
    /// is left uninitialized, so the second `sumByDouble` call reuses the first
    /// call's result.
    @Test
    func testSumByDoubleLiteralInImportedInlineKIR() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println("abc".sumByDouble { it.code.toDouble() / 2 })
            println("".sumByDouble { it.code.toDouble() / 2 })
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
            #expect(normalizedStdout == "147.0\n0.0\n")
        }
    }

    /// Imported runtime-backed interface getters retain a direct runtime target
    /// in the shared artifact. They must not be redirected to an itable property
    /// slot that the runtime collection boxes do not register.
    @Test
    func testImportedCollectionSizeGetterUsesDirectBridge() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun collectionSize(values: Collection<Int>): Int = values.size

        fun main() {
            println(collectionSize(listOf(1, 2, 3)))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ImportedCollectionSizeGetter",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let body = try findKIRFunctionBody(
                named: "collectionSize",
                in: module,
                interner: ctx.interner
            )
            let directGetterLinks = body.compactMap { instruction -> String? in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction
                else {
                    return nil
                }
                // Runtime intrinsics may use a direct KIR callee without a Sema symbol.
                return symbol.flatMap { sema.symbols.externalLinkName(for: $0) }
                    ?? ctx.interner.resolve(callee)
            }
            #expect(directGetterLinks.contains(try runtimeABICallee("collection_size")))
            #expect(!body.contains { instruction in
                guard case .virtualCall = instruction else { return false }
                return true
            })

            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "3\n")
        }
    }

    /// STDLIB-ARTIFACT-019: `List.filterIsInstance<R>()` is an inline reified HOF.
    /// The shared stdlib artifact's function metadata must round-trip the set of
    /// reified type parameter indices, so the consumer's call lowerer appends the
    /// runtime type-token argument required by the imported inline KIR body.
    @Test
    func testFilterIsInstanceSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val mixed: List<Any> = listOf(1, "hello", 2, "world", 3)
            val strings = mixed.filterIsInstance<String>()
            val ints = mixed.filterIsInstance<Int>()
            println(strings)
            println(ints)
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
            #expect(normalizedStdout == "[hello, world]\n[1, 2, 3]\n")
        }
    }

    /// STDLIB-ARTIFACT-020: variance generics with `String` crossing interface
    /// dispatch boundaries (covariant `Producer`, contravariant `Consumer`,
    /// invariant `Container`) require the `virtualCall` emission to bridge
    /// `String` aggregate values to/from the erased raw-pointer ABI used by the
    /// itable function pointer. A user-defined method named `produce` must not
    /// be mistaken for the coroutine builder `produce` during lowering.
    @Test
    func testVarianceGenericsStringItableBridgeSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = try diffCaseSource("variance_generics.kt", file: #filePath)

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
            #expect(normalizedStdout == "variance test\nconsumed: hello from feeder\nstored: new value\ninvariant value\n")
        }
    }

    /// KSP-625: `ArrayDeque<E>` is bundled Kotlin source, so the shared artifact
    /// path exercises two imported-library gaps it surfaced: a constructor call
    /// with explicit type arguments (`ArrayDeque<Int>()`) was rejected because
    /// imported constructor signatures reported zero class type parameters, and
    /// `println(deque)` printed `<object 0x...>` because the imported
    /// `toString()` override was skipped for being flagged synthetic.
    @Test
    func testArrayDequeThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val deque = ArrayDeque<Int>()
            deque.addLast(2)
            deque.addFirst(1)
            deque.addLast(3)
            println(deque.size)
            println(deque.first())
            println(deque.last())
            println(deque[1])
            println(deque)
            println(deque.removeFirst())
            println(deque.removeLast())
            println(deque.isEmpty())
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
            #expect(normalizedStdout == """
                3
                1
                3
                2
                [1, 2, 3]
                1
                3
                false

                """)
        }
    }

    /// STDLIB-ARTIFACT-003: an inline stdlib function whose body reads a
    /// property of a bundled Kotlin class (`Map.plus` reading `pair.first` /
    /// `pair.second`) links through the shared artifact.
    ///
    /// The inline body is serialized as KIR text and re-lowered in the consumer.
    /// Its getter call is recorded with the pre-mangling callee spelling
    /// (`get`) plus the library's link name for it (`kk_fn_get_<id>`). Only the
    /// latter names anything the consumer can call: the accessor is compiled
    /// into the library's own object and the consumer owns no symbol for it, so
    /// dropping the link name left an `undefined reference to 'get'` at link
    /// time. This only became reachable once `Pair`/`Triple` moved from
    /// synthetic runtime stubs (whose accessors were external `kk_pair_*`
    /// bridges, named identically in both modules) to bundled Kotlin source.
    @Test
    func testInlineStdlibFunctionReadingBundledClassPropertySharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val base: Map<String, Int> = mapOf("a" to 1)
            println(base.plus("b" to 2))
            println(emptyMap<String, Int>().plus("c" to 3))
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
            #expect(normalizedStdout == "{a=1, b=2}\n{c=3}\n")
        }
    }

    /// An `override` member is implicitly open in Kotlin, but the serializer
    /// dropped that, so an imported `AbstractMap.size` decoded as final and
    /// consumers could not override it.
    @Test
    func testAbstractMapSizeOverrideThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.collections.AbstractMap
        import kotlin.collections.Map
        import kotlin.collections.Set

        class ObservedMap : AbstractMap<String?, Int?>() {
            override val entries: Set<Map.Entry<String?, Int?>>
                get() = emptyMap<String?, Int?>().entries

            override val size: Int
                get() = 2
        }

        fun customMapCount(): Int {
            return ObservedMap().size
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "AbstractMapSizeOverrideArtifact",
                emit: .kirDump,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Overriding imported AbstractMap.size should not be rejected: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    /// `LinkedHashSet()` lowers to the `__kk_linked_hash_set_of` runtime factory, so the
    /// returned box never passes `kk_object_new` and never received the
    /// constructor-site `kk_object_register_vtable_method` registrations. Once
    /// `size` imported as the (Kotlin-correct) open member it is, a subclass in
    /// the same module marked its slot virtual and `base.size` trapped in
    /// `kk_vtable_lookup`. The lowering pass now registers the nominal vtable
    /// implementations on factory-produced boxes.
    @Test
    func testLinkedHashSetOpenMembersDispatchOnFactoryBox() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        class Tags : LinkedHashSet<String>()

        fun makeSet(): LinkedHashSet<String> {
            val s = LinkedHashSet<String>()
            s.add("x")
            return s
        }

        fun main() {
            val t = Tags()
            t.add("kotlin")
            println(t.size)
            println(t.contains("kotlin"))

            val base = LinkedHashSet<String>()
            base.add("a")
            println(base.size)
            println(base.contains("a"))

            println(makeSet().size)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "LinkedHashSetFactoryVtable",
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
            #expect(normalizedStdout == "1\ntrue\n1\ntrue\n1\n")
        }
    }
}
