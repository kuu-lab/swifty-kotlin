@testable import CompilerBackend
@testable import CompilerCore
import Foundation

#if canImport(Testing)
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

/// BUG-142: `++` / `--` used in expression position (`values[index++]`) was parsed
/// but the mutation was dropped, so user-defined iterators over a collection held
/// in an instance field never advanced and looped forever.
@Suite
struct CodegenBackendIncrementExpressionPositionTests {
    @Test
    func testUserDefinedIteratorOverInstanceFieldCollection() throws {
        let source = """
        class Entry(val first: Int, val second: Int)

        class EntryIterator(private val values: MutableList<Entry>) {
            private var index = 0
            operator fun hasNext(): Boolean = index < values.size
            operator fun next(): Entry = values[index++]
        }

        class EntryBag(private val values: MutableList<Entry>) {
            operator fun iterator(): EntryIterator = EntryIterator(values)
        }

        fun main() {
            val bag = EntryBag(mutableListOf(Entry(1, 2), Entry(3, 4), Entry(5, 6)))
            val entries = bag.iterator()
            var sum = 0
            while (entries.hasNext()) {
                val e = entries.next()
                sum += e.first + e.second
            }
            println("manual=" + sum)

            var forSum = 0
            for (e in EntryBag(mutableListOf(Entry(1, 2), Entry(3, 4)))) {
                forSum += e.first + e.second
            }
            println("forin=" + forSum)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UserDefinedIteratorInstanceField",
            expected: "manual=21\nforin=10\n"
        )
    }

    @Test
    func testUserDefinedIteratorOverInstanceFieldIntArray() throws {
        let source = """
        class IntArrayIterator(private val values: IntArray) {
            private var index = 0
            operator fun hasNext(): Boolean = index < values.size
            operator fun next(): Int = values[index++]
        }

        class IntArrayBag(private val values: IntArray) {
            operator fun iterator(): IntArrayIterator = IntArrayIterator(values)
        }

        fun main() {
            var sum = 0
            for (v in IntArrayBag(intArrayOf(1, 2, 3, 4))) {
                sum += v
            }
            println("intarray=" + sum)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UserDefinedIteratorIntArrayField",
            expected: "intarray=10\n"
        )
    }

    @Test
    func testIncrementDecrementInExpressionPosition() throws {
        let source = """
        class Counter {
            var value = 0
            fun postfix(): Int = value++
            fun prefix(): Int = --value
        }

        fun main() {
            var i = 0
            val a = arrayOf(10, 20, 30)
            println("read=" + a[i++] + " i=" + i)
            println("post=" + i++ + " i=" + i)
            println("pre=" + ++i + " i=" + i)
            println("dec=" + i-- + " i=" + i)

            val counter = Counter()
            println("cpost=" + counter.postfix() + " value=" + counter.value)
            println("cpre=" + counter.prefix() + " value=" + counter.value)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IncrementExpressionPosition",
            expected: """
            read=10 i=1
            post=1 i=2
            pre=3 i=3
            dec=3 i=2
            cpost=0 value=1
            cpre=0 value=0

            """
        )
    }

    @Test
    func testLocalInitializedFromVariableSnapshotsValue() throws {
        let source = """
        fun main() {
            var source = 1
            val snapshot = source
            source += 41
            println("snapshot=" + snapshot + " source=" + source)

            var text = "x"
            val copied = text
            text += "y"
            println("copied=" + copied + " text=" + text)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LocalSnapshotFromVariable",
            expected: "snapshot=1 source=42\ncopied=x text=xy\n"
        )
    }

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
}
#endif
