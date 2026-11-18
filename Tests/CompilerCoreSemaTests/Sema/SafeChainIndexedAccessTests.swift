#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SafeChainIndexedAccessTests {
    @Test func safeChainIndexedAccessResolvesOperatorOnNonNullReceiver() throws {
        let ctx = makeContextFromSource("""
        class StreamConfig
        class SourceConfig(val streamConfigs: Map<String, StreamConfig>)
        class Box(val values: List<Int>)

        fun mapLookup(source: SourceConfig?, name: String): StreamConfig? = source?.streamConfigs[name]
        fun listLookup(box: Box?): Int? = box?.values[0]
        fun nonNullAssertLookup(box: Box?): Int = box?.values!![0]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var nullableIndexedCount = 0
        var assertedIndexedCount = 0
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .indexedAccess(receiver, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { continue }
            let id = ExprID(rawValue: Int32(index))
            let type = try #require(sema.bindings.exprType(for: id))
            if case .safeMemberCall = ast.arena.expr(receiver) {
                nullableIndexedCount += 1
                #expect(sema.types.nullability(of: type) == .nullable)
            } else if case .nullAssert = ast.arena.expr(receiver) {
                assertedIndexedCount += 1
                #expect(sema.types.nullability(of: type) == .nonNull)
            }
        }
        #expect(nullableIndexedCount == 2)
        #expect(assertedIndexedCount == 1)
    }
}
#endif
