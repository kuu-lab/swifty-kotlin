#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct RangeJoinToStringPairCaptureTests {
    /// KUU-1871: a captured Pair.first is a String result for the range's
    /// source-backed Iterable.joinToString transform.
    @Test
    func capturedPairFirstSatisfiesRangeJoinToStringTransform() throws {
        let ctx = makeContextFromSource("""
        class Solver {
            fun join(input: Pair<String, List<Int>>): Pair<String, List<Int>> =
                (0..4).joinToString("?") { input.first } to (0..4).flatMap { input.second }
        }
        fun main() { println(Solver().join("abc" to listOf(1, 2))) }
        """)

        try runSema(ctx)

        let userFiles = ctx.sourceManager.fileIDs().filter {
            ctx.sourceManager.origin(of: $0) == .user
        }
        let userErrors = ctx.diagnostics.diagnostics.filter { diagnostic in
            diagnostic.severity == .error
                && diagnostic.primaryRange.map { userFiles.contains($0.start.file) } == true
        }
        let ast = try #require(ctx.ast)
        let retainsPairShapeAndFlatMap = ast.arena.exprs.indices.contains { index in
            let id = ExprID(rawValue: Int32(index))
            guard ast.arena.isInfixCall(id),
                  case let .memberCall(joinedExpr, name, _, args, _) = ast.arena.expr(id),
                  ctx.interner.resolve(name) == "to",
                  case let .memberCall(_, joinName, _, _, _) = ast.arena.expr(joinedExpr),
                  ctx.interner.resolve(joinName) == "joinToString",
                  args.count == 1,
                  case let .memberCall(_, flatMapName, _, _, _) = ast.arena.expr(args[0].expr)
            else { return false }
            return ctx.interner.resolve(flatMapName) == "flatMap"
        }
        #expect(retainsPairShapeAndFlatMap, "The parsed Pair expression must retain both calls and infix 'to'.")
        #expect(userErrors.isEmpty, "Unexpected user-source diagnostics: \(userErrors)")
    }
}
#endif
