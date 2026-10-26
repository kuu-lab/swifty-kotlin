#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// KSP-651 / KUU-1359: `iterator {}` is produced through the coroutine/CPS
    /// builder path whose runtime ABI takes (fnPtr, closureRaw) — the env slot
    /// carries the builder lambda's captures and must always be present, even
    /// when the block captures nothing.
    @Test func testIteratorBuilderPassesFnAndEnvToBuilder() throws {
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

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let argumentCounts = findAllKIRFunctions(in: module).flatMap { function -> [Int] in
            function.body.compactMap { instruction -> Int? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      callee == ctx.interner.intern(runtimeCallee(.iteratorBuilderBuild))
                else { return nil }
                return arguments.count
            }
        }

        #expect(!argumentCounts.isEmpty, "Expected an __kk_iterator_builder_build call")
        #expect(
            argumentCounts.allSatisfy { $0 == 2 },
            "Iterator builder must receive (fnPtr, closureRaw), got argument counts: \(argumentCounts)"
        )
    }
}
#endif
