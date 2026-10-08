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

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let sourcePath = ctx.options.inputs[0]
        let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: sourcePath))
        let lambdaSymbols = Set(try findKIRLambdaFunctions(in: ctx).map(\.symbol))
        let sourceFunctions = findAllKIRFunctions(in: module).filter { function in
            function.sourceRange?.start.file == sourceFileID || lambdaSymbols.contains(function.symbol)
        }
        let callees = sourceFunctions.flatMap { function -> [String] in
            return extractCallees(from: function.body, interner: ctx.interner)
        }

        #expect(!sourceFunctions.isEmpty, "Expected to find functions from \(sourcePath)")
        #expect(callees.contains(runtimeCallee(.sequenceBuilderBuild)), "Expected sequence builder runtime construction, got: \(callees)")
        #expect(callees.contains(runtimeCallee(.iteratorBuilderBuild)), "Expected iterator builder runtime construction, got: \(callees)")
        #expect(callees.contains(runtimeCallee(.sequenceBuilderYield)), "Expected source builder lambda to yield through runtime, got: \(callees)")
        #expect(!callees.contains(runtimeCallee(.durationTimesInt)), "Builder loop Int arithmetic must not use Duration.times(Int), got: \(callees)")
    }
}
#endif
