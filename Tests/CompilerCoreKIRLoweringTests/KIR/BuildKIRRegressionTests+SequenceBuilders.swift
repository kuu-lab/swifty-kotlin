#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
        #expect(!callees.contains("kk_duration_times_int"), "Builder loop Int arithmetic must not use Duration.times(Int), got: \(callees)")
    }

    /// KUU-3075: a `sequence {}`/`iterator {}` block that captures the outer
    /// class receiver must keep its own `SequenceScope` receiver param as the
    /// implicit receiver. Rebinding the packed/raw `this` capture used to
    /// overwrite it, so `yield` was emitted with the captured class handle as
    /// the builder handle and panicked at runtime (invalid builder handle).
    @Test func testBuilderLambdaCapturingOuterReceiverKeepsBuilderReceiver() throws {
        let source = """
        class Grid(val w: Int) {
            fun it(): Iterator<Int> = iterator {
                for (x in 0 until w) {
                    yield(x)
                }
            }
            fun seq(): Sequence<Int> = sequence {
                yield(w)
            }
            fun multi(offset: Int): Iterator<Int> {
                val base = offset
                return iterator {
                    yield(w + base)
                }
            }
        }
        fun main() {
            for (x in Grid(2).it()) {
                println(x)
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let lambdaSymbols = Set(try findKIRLambdaFunctions(in: ctx).map(\.symbol))
        let builderYieldCallees: Set<InternedString> = [
            ctx.interner.intern("__kk_sequence_builder_yield"),
            ctx.interner.intern("__kk_iterator_builder_yield"),
        ]

        var checkedYields = 0
        for function in findAllKIRFunctions(in: module) where lambdaSymbols.contains(function.symbol) {
            // The builder lambda takes (closureEnv, receiver); `yield`'s first
            // argument must be that receiver param, not a restored capture.
            guard let receiverSymbol = function.params.last?.symbol else { continue }
            for instruction in function.body {
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      builderYieldCallees.contains(callee),
                      let builderHandle = arguments.first
                else { continue }
                checkedYields += 1
                #expect(
                    module.arena.expr(builderHandle) == .symbolRef(receiverSymbol),
                    "yield must use the SequenceScope receiver param as the builder handle, got \(module.arena.expr(builderHandle)) in \(ctx.interner.resolve(function.name))"
                )
            }
        }
        #expect(checkedYields == 3, "Expected yields from the three builder lambdas, found \(checkedYields)")
    }
}
#endif
