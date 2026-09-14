#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCollectionIteratorTests {
    @Test func testCodegenCollectionIteratorUsesListRuntimeHelper() throws {
        let source = """
        fun firstList(values: List<Int>): Int {
            val iterator = values.iterator()
            return if (iterator.hasNext()) iterator.next() else -1
        }

        fun firstSet(values: Set<Int>): Int {
            val iterator = values.iterator()
            return if (iterator.hasNext()) iterator.next() else -1
        }

        fun firstCollection(values: Collection<Int>): Int {
            val iterator = values.iterator()
            return if (iterator.hasNext()) iterator.next() else -1
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CollectionIteratorRuntime", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            for functionName in ["firstList", "firstSet", "firstCollection"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(callees.contains("kk_list_iterator"), "\(functionName) should call kk_list_iterator")
                #expect(!callees.contains("kk_range_iterator"), "\(functionName) should not call kk_range_iterator")
            }
        }
    }

    @Test func testIteratorIdentityPreservesStateAndForLoopControlFlow() throws {
        let source = """
        private class Probe : Iterator<String?> {
            private var index = 0
            var hasNextCalls = 0
            var nextCalls = 0

            override operator fun hasNext(): Boolean {
                hasNextCalls += 1
                return index < 2
            }

            override operator fun next(): String? {
                nextCalls += 1
                val result = if (index == 0) "first" else null
                index += 1
                return result
            }
        }

        fun main() {
            val iterator = Probe()
            val same = iterator.iterator()

            println(same === iterator)
            println(same === iterator.iterator())
            println(iterator.hasNextCalls)
            println(iterator.nextCalls)
            println(iterator.hasNext())
            println(iterator.next())
            println(iterator.nextCalls)

            val controlled = Probe()
            for (value in controlled) {
                if (value == "first") continue
                println(value)
                break
            }
            println(controlled.hasNextCalls)
            println(controlled.nextCalls)
        }
        """

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        try withTemporaryFile(contents: source) { path in
            let options = CompilerOptions(
                moduleName: "IteratorIdentityRuntime",
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
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == """
                true
                true
                0
                0
                true
                first
                1
                null
                2
                2

                """
            )
        }
    }
}
#endif
