@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    @Test(arguments: [false, true])
    func testUserCollectionClassNamesPreserveDispatch(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let source = try diffCaseSource("kuu1939_user_collection_class_names.kt", file: #filePath)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "UserCollectionClassNames",
                emit: .executable, outputPath: outputBase,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            user-add-called
            false
            user-HashMap.get
            true
            user-MutableSet
            true
            user-add-called
            false
            user-HashMap.get
            user-LinkedHashSet.add
            user-MutableMap.get
            user-LinkedHashMap.get
            true
            false
            9

            """)
        }
    }

    private static func abstractCollectionSource() throws -> String {
        try diffCaseSource("bug_200_precompiled_abstract_collection.kt", file: #filePath)
    }

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

    @Test
    func testListReturningExtensionsKeepListTypeIdentityThroughDefaultArtifact() throws {
        _ = try testStdlibArtifactPath()
        try withTemporaryFile(contents: """
        fun main() {
            val values = listOf("a", "b")
            val mapped: List<String> = values.map { it }
            val sliced: List<String> = values.slice(0..1)
            val sublisted: List<String> = values.subList(0, 2)
            println(mapped.size)
            println(sliced.size)
            println(sublisted.size)
        }
        """) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ListReturnDefaultArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: true,
                allowDefaultStdlibLibrary: true
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "2\n2\n2\n")
        }
    }

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
