#if canImport(Testing)
@testable import CompilerCore
import Testing

// ARCH-019: every lowering pass must keep `instructionLocations` parallel to
// `body`. This test lowers a source that exercises passes which rewrite,
// expand, and synthesize instructions (tailrec, for loops, when, lambdas,
// try/catch, coroutines) and asserts the invariant holds for every function.
struct LoweringInstructionLocationParityTests {
    @Test
    func testInstructionLocationsStayParallelAcrossLoweringPasses() throws {
        let source = """
        tailrec fun countdown(n: Int, acc: Int): Int {
            if (n == 0) return acc
            return countdown(n - 1, acc + n)
        }
        fun pick(x: Int): String = when (x) {
            0 -> "zero"
            in 1..3 -> "small"
            else -> "big"
        }
        suspend fun fetchAll(items: List<Int>): Int {
            var total = 0
            for (item in items) {
                total += item
            }
            return total
        }
        fun risky(x: Int): Int {
            try {
                val fn = { v: Int -> v * 2 }
                return fn(x)
            } catch (e: Exception) {
                return -1
            } finally {
                println("done")
            }
        }
        fun main() {
            println(countdown(10, 0))
            println(pick(2))
            println(risky(4))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "LocParity", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            var functionCount = 0
            var hasNonNilLocation = false
            for decl in module.arena.declarations {
                guard case let .function(function) = decl else { continue }
                functionCount += 1
                #expect(
                    function.instructionLocations.count == function.body.count,
                    Comment(rawValue: "\(ctx.interner.resolve(function.name)): instructionLocations "
                        + "has \(function.instructionLocations.count) entries for "
                        + "\(function.body.count) instructions")
                )
                if function.instructionLocations.contains(where: { $0 != nil }) {
                    hasNonNilLocation = true
                }
            }
            #expect(functionCount > 0)
            #expect(hasNonNilLocation, "all instruction locations were lost during lowering")
        }
    }
}
#endif
