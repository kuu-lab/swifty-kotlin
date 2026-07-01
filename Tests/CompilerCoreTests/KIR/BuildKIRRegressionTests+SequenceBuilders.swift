#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test func testBuilderLoopArithmeticDoesNotResolveToDurationOperator() throws {
        let source = """
        fun main() {
            val seq = sequence {
                for (i in 1..3) {
                    yield(i * i)
                }
            }
            val iter = iterator {
                for (i in 1..3) {
                    yield(i * i)
                }
            }
            for (x in seq) {
                println(x)
            }
            for (x in iter) {
                println(x)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: path))
            let sourceFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                let name = ctx.interner.resolve(function.name)
                let isSourceFunction = function.sourceRange?.start.file == sourceFileID
                let isGeneratedLambdaFunction = name.contains("kk_lambda_")
                return isSourceFunction || isGeneratedLambdaFunction ? function : nil
            }
            let callees = sourceFunctions.flatMap { function -> [String] in
                return extractCallees(from: function.body, interner: ctx.interner)
            }

            #expect(!sourceFunctions.isEmpty, "Expected to find functions from \(path)")
            #expect(callees.contains("kk_sequence_builder_build"), "Expected sequence builder runtime construction, got: \(callees)")
            #expect(callees.contains("kk_iterator_builder_build"), "Expected iterator builder runtime construction, got: \(callees)")
            #expect(callees.contains("kk_sequence_builder_yield"), "Expected source builder lambda to yield through runtime, got: \(callees)")
            #expect(!callees.contains("kk_duration_times_int"), "Builder loop Int arithmetic must not use Duration.times(Int), got: \(callees)")
        }
    }
}
#endif
