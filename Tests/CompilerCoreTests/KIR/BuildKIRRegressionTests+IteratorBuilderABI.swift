#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    /// KSP-651: `iterator {}` is produced through the coroutine/CPS builder path, so its
    /// runtime construction must keep the single builder-lambda argument instead of being
    /// expanded like a collection HOF closure (which passes an invalid builder handle).
    @Test func testIteratorBuilderKeepsSingleBuilderArgument() throws {
        let source = """
        fun main() {
            val iter = iterator {
                yield(1)
                yield(2)
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
            let argumentCounts = findAllKIRFunctions(in: module).flatMap { function -> [Int] in
                function.body.compactMap { instruction -> Int? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "__kk_iterator_builder_build"
                    else { return nil }
                    return arguments.count
                }
            }

            #expect(!argumentCounts.isEmpty, "Expected an __kk_iterator_builder_build call")
            #expect(
                argumentCounts.allSatisfy { $0 == 1 },
                "Iterator builder must receive exactly the builder lambda, got argument counts: \(argumentCounts)"
            )
        }
    }
}
#endif
