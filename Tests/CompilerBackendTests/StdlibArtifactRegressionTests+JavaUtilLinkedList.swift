@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-3259: artifact-backed List equality must accept java.util.LinkedList.
    @Test
    func testJavaUtilLinkedListListEqualityInsideFreshStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import java.util.LinkedList

        fun main() {
            val linked = LinkedList<Int>()
            linked.add(1)
            val erased: Any = linked
            println(erased is List<*>)
            println(listOf(1) == linked)
            println(mutableListOf(1) == linked)
            val deque = ArrayDeque<Int>()
            deque.add(1)
            println(deque.equals(erased))
            println(linked.equals(listOf(1)))
        }
        """
        let expected = """
        true
        true
        true
        true
        true

        """

        let output = try Self.runLinkedListSources(
            [source], optLevel: .O0, stdlibLibraryPath: artifactPath
        )
        #expect(output == expected, "fresh stdlib artifact at O0")
    }

    /// KUU-2035: preserve JVM Unit local, return, argument, and property boundaries.
    @Test
    func testJavaLinkedListPlatformUnitThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("java_util_linked_list_platform_unit.kt", file: #filePath)
        let expected = """
        kotlin.Unit
        size:1
        kotlin.Unit
        kotlin.Unit
        kotlin.Unit
        null
        null
        null
        kotlin.Unit
        kotlin.Unit
        kotlin.Unit
        kotlin.Unit
        kotlin.Unit
        npe:argument
        kotlin.Unit
        null
        npe:bounded-argument
        npe:local-argument
        npe:function
        npe:receiver
        npe:function-receiver
        null
        null
        null
        null
        null
        null
        null
        null
        null
        null
        null
        kotlin.Unit
        null

        """
        let negativeSource = """
        import java.util.LinkedList
        fun ordinary(value: Unit?): Unit = value
        fun nullableElement(q: LinkedList<Unit?>): Unit = q.peekLast()
        fun safeReceiver(q: LinkedList<Unit>?): Unit = q?.peekLast()
        """
        for optLevel in [OptimizationLevel.O0, .O2] {
            for stdlibLibraryPath in [nil, artifactPath] {
                let output = try Self.runLinkedListSources([source], optLevel: optLevel,
                                                          stdlibLibraryPath: stdlibLibraryPath)
                #expect(output == expected, "Unit! at \(optLevel), artifact: \(stdlibLibraryPath != nil)")
                try withTemporaryFiles(contents: [negativeSource]) { inputs in
                    let options = CompilerOptions(
                        moduleName: "PlatformUnitNegative", inputs: inputs,
                        outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                        emit: .kirDump, target: defaultTargetTriple(), optLevel: optLevel,
                        includeStdlib: stdlibLibraryPath == nil, stdlibLibraryPath: stdlibLibraryPath,
                        allowDefaultStdlibLibrary: false
                    )
                    let ctx = CompilationContext(options: options, sourceManager: SourceManager(),
                        diagnostics: DiagnosticEngine(), interner: StringInterner())
                    try runSema(ctx)
                    let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                    #expect(errors.count == 3 && errors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" }, "\(errors)")
                }
            }
        }
    }

    /// KUU-2022: retain the unchanged upstream generic return through both routes.
    @Test
    func testJavaLinkedListPlatformReturnsThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/JavaLinkedListPlatformReturn")
        let stack = try String(contentsOf: fixture.appendingPathComponent("Stack2.kt"), encoding: .utf8)
        let main = try String(contentsOf: fixture.appendingPathComponent("Main.kt"), encoding: .utf8)
        let reproducer = try diffCaseSource("java_util_linked_list_platform_return.kt", file: #filePath)
        let expectedReproducer = """
        7
        int:8:1
        unary:-7
        bool:true:false:false
        condition:false
        when:false
        long:2147483649
        double:2.0
        empty:null:0
        null
        null
        concat:null
        [1, null]
        string:5:hello:1
        clear:null:0
        nullable-empty:null
        nullable-value:9:1
        nullable-null:null:null:2
        npe:local
        npe:return
        npe:bound
        npe:argument
        npe:function
        npe:unary
        npe:boolean
        npe:boolean-not
        npe:condition
        npe:when
        short-circuit:false:true
        nullable-string:null:1

        """
        let expectedStack = """
        peek:Stack is empty!
        pop:Stack is empty!
        stack:true:0

        """
        for optLevel in [OptimizationLevel.O0, .O2] {
            for stdlibLibraryPath in [nil, artifactPath] {
                let output = try Self.runLinkedListSources(
                    [stack,
                     main.replacingOccurrences(of: "fun main() {", with: "fun runStackRegression() {"),
                     reproducer.replacingOccurrences(of: "fun main() {", with: "fun runPlatformReturnRegression() {"),
                     "fun main() { runPlatformReturnRegression(); runStackRegression() }"],
                    optLevel: optLevel, stdlibLibraryPath: stdlibLibraryPath
                )
                #expect(output == expectedReproducer + expectedStack,
                        "platform return and unchanged Stack2 at \(optLevel), artifact: \(stdlibLibraryPath != nil)")
                try withTemporaryFiles(contents: ["""
                import java.util.LinkedList
                fun <T> bad(value: T?): T = value
                fun badNullableElement(q: LinkedList<Int?>): Int = q.peekLast()
                """]) { inputs in
                    let options = CompilerOptions(
                        moduleName: "KUU2022Negative", inputs: inputs,
                        outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                        emit: .kirDump, target: defaultTargetTriple(), optLevel: optLevel, includeStdlib: stdlibLibraryPath == nil,
                        stdlibLibraryPath: stdlibLibraryPath, allowDefaultStdlibLibrary: false
                    )
                    let ctx = CompilationContext(options: options, sourceManager: SourceManager(),
                        diagnostics: DiagnosticEngine(), interner: StringInterner())
                    try runSema(ctx)
                    let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                    #expect(errors.filter { $0.code == "KSWIFTK-TYPE-0001" }.count == 2, "\(errors)")
                }
            }
        }
    }

    /// KUU-2013: peekLast preserves element types, nullability, and contents.
    @Test
    func testJavaUtilLinkedListPeekLastThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("java_util_linked_list_peek_last.kt", file: #filePath)
        let expectedOutput = """
        null
        b
        2
        null
        string-empty:null:0
        string-single:head:1
        string-tail:4:tail:2:head
        string-pop:tail:head:1
        string-clear:null:0
        int-empty:null:0
        int-single:8:1
        int-tail:43:42:2:7
        int-pop:42:7:1
        int-clear:null:0
        nullable-int-empty:null:0
        nullable-int-single:null:1
        nullable-int-value:10:2
        nullable-int-tail:null:null:3
        nullable-int-pop:null:9:2
        nullable-int-clear:null:0
        nullable-string-empty:null:0
        nullable-string-single:1:1
        nullable-string-tail:null:null:2:a
        nullable-string-clear:null:0
        stack-peek:Stack is empty!
        stack-pop:Stack is empty!
        stack:true:0

        """

        for optLevel in [OptimizationLevel.O0, .O2] {
            for stdlibLibraryPath in [nil, artifactPath] {
                let output = try Self.runLinkedListSources(
                    [source],
                    optLevel: optLevel,
                    stdlibLibraryPath: stdlibLibraryPath
                )
                #expect(output == expectedOutput,
                        "peekLast at \(optLevel), artifact: \(stdlibLibraryPath != nil)")
            }
        }
    }

    /// KUU-1858: run the reported LinkedList reproducer and pinned Queue
    /// consumer against source stdlib and one freshly emitted artifact at O0/O2.
    /// Queue.kt and Graph.kt provenance is pinned in the diff-case fixture; the
    /// full Graph consumer additionally depends on KUU-1860's putIfAbsent API.
    /// Pinned Graph Main input:
    /// ```kotlin
    /// import structures.*
    /// fun main() {
    ///     val graph = Graph<Int>()
    ///     for (v in 1..4) graph.addVertex(v)
    ///     graph.addEdge(1, 2)
    ///     graph.addEdge(1, 3)
    ///     graph.addEdge(2, 4)
    ///     println(graph.connectedVertexes(1).joinToString(","))
    ///     println(graph.breadthFirstTraversal().joinToString(","))
    /// }
    /// ```
    /// Expected stdout after KUU-1860 lands: `2,3` then `1,2,3,4`.
    @Test
    func testJavaUtilLinkedListConsumersThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let reproducer = try diffCaseSource("java_util_linked_list.kt", file: #filePath)
            .replacingOccurrences(
                of: "fun main() {",
                with: "fun runLinkedListRegression() {"
            )
        #expect(reproducer.contains("fun runLinkedListRegression() {"))

        let queueSource = """
        package structures

        import java.util.LinkedList

        /**
         * Queue is a data structure that follows the FIFO (first in, first out) principle
         * LIFO implies that the element that is inserted first, comes out first
         * The main operations:
         * 1) enqueue - inserts an element at the end of the queue
         * 2) dequeue - removes an element from the beginning of the queue
         * All these operations performed in O(1) time.
         */
        class Queue<T> {
            private val data = LinkedList<T>()

            val isEmpty: Boolean
                get() = data.isEmpty()

            val size: Int
                get() = data.size

            fun enqueue(item: T) {
                data.add(item)
            }

            fun dequeue(): T {
                if (isEmpty) throw IllegalStateException("The queue is empty")
                return data.removeFirst()
            }

            fun peek(): T {
                if (isEmpty) throw IllegalStateException("The queue is empty")
                return data.first
            }

            fun clear() {
                data.clear()
            }
        }
        """
        let mainSource = """
        import structures.*

        fun main() {
            runLinkedListRegression()
            val queue = Queue<Int>()
            queue.enqueue(3)
            queue.enqueue(7)
            println(queue.peek())
            println(queue.dequeue())
            println(queue.dequeue())
            println(queue.isEmpty)
        }
        """
        let expectedOutput = """
        1
        3
        3
        7
        null
        true
        null
        remove:null
        first:null
        8
        4
        true 0
        2,3
        3
        3
        7
        true

        """

        for optLevel in [OptimizationLevel.O0, .O2] {
            let sourceOutput = try Self.runLinkedListSources(
                [reproducer, queueSource, mainSource],
                optLevel: optLevel,
                stdlibLibraryPath: nil
            )
            #expect(sourceOutput == expectedOutput, "source stdlib at \(optLevel)")

            let artifactOutput = try Self.runLinkedListSources(
                [reproducer, queueSource, mainSource],
                optLevel: optLevel,
                stdlibLibraryPath: artifactPath
            )
            #expect(artifactOutput == expectedOutput, "fresh stdlib artifact at \(optLevel)")
        }
    }

    private static func runLinkedListSources(
        _ sources: [String],
        optLevel: OptimizationLevel,
        stdlibLibraryPath: String?
    ) throws -> String {
        var normalizedOutput: String?
        try withTemporaryFiles(contents: sources) { inputs in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: "KUU1858LinkedList",
                inputs: inputs,
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: stdlibLibraryPath == nil,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            )
            let context = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            guard result.exitCode == 0 else {
                throw TestCompilationFailure(
                    description: "KUU-1858 executable failed at \(optLevel): \(result.stderr)"
                )
            }
            #expect(result.stderr.isEmpty, "LinkedList executable stderr: \(result.stderr)")
            normalizedOutput = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
        }
        guard let normalizedOutput else {
            throw TestCompilationFailure(description: "KUU-1858 fixture did not run")
        }
        return normalizedOutput
    }
}
