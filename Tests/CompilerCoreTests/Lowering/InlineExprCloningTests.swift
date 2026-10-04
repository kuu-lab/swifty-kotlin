#if canImport(Testing)
@testable import CompilerCore
import Testing

struct InlineExprCloningTests {
    @Test
    func testCloneOrReuseExprClonesANewExpressionWithTheSameKindAndType() {
        let arena = KIRArena()
        let types = TypeSystem()
        let source = arena.appendExpr(.intLiteral(42), type: types.intType)
        var localExprMap: [KIRExprID: KIRExprID] = [:]

        let cloned = InlineExprCloning.cloneOrReuseExpr(source, localExprMap: &localExprMap, in: arena)

        #expect(cloned != source)
        #expect(arena.expr(cloned) == .intLiteral(42))
        #expect(arena.exprType(cloned) == types.intType)
    }

    @Test
    func testCloneOrReuseExprReusesTheSameCloneForARepeatedSource() {
        let arena = KIRArena()
        let types = TypeSystem()
        let source = arena.appendExpr(.intLiteral(1), type: types.intType)
        var localExprMap: [KIRExprID: KIRExprID] = [:]

        let first = InlineExprCloning.cloneOrReuseExpr(source, localExprMap: &localExprMap, in: arena)
        let countAfterFirst = arena.expressions.count
        let second = InlineExprCloning.cloneOrReuseExpr(source, localExprMap: &localExprMap, in: arena)

        #expect(second == first)
        #expect(arena.expressions.count == countAfterFirst)
    }

    @Test
    func testCloneOrReuseExprAppliesTheSubstituteTypeClosureToTheClonesType() {
        let arena = KIRArena()
        let types = TypeSystem()
        let source = arena.appendExpr(.intLiteral(1), type: types.intType)
        var localExprMap: [KIRExprID: KIRExprID] = [:]

        let cloned = InlineExprCloning.cloneOrReuseExpr(
            source,
            localExprMap: &localExprMap,
            in: arena,
            substituteType: { _ in types.stringType }
        )

        #expect(arena.expr(cloned) == .intLiteral(1))
        #expect(arena.exprType(cloned) == types.stringType)
    }

    @Test
    func testCloneOrReuseExprDefaultsToLeavingTheTypeUnchanged() {
        let arena = KIRArena()
        let types = TypeSystem()
        let source = arena.appendExpr(.intLiteral(1), type: types.intType)
        var localExprMap: [KIRExprID: KIRExprID] = [:]

        let cloned = InlineExprCloning.cloneOrReuseExpr(source, localExprMap: &localExprMap, in: arena)

        #expect(arena.exprType(cloned) == types.intType)
    }

    // A serialized imported-inline body can carry a `KIRExprID` with no
    // backing expression. `appendTemporary` and this fallback both derive
    // their new id from `arena.expressions.count` at the same point, so they
    // agree on the id the clone receives.
    @Test
    func testCloneOrReuseExprFallsBackToATemporaryWhenTheSourceHasNoRecordedExpression() {
        let arena = KIRArena()
        let types = TypeSystem()
        let missingSource = KIRExprID(rawValue: 999)
        var localExprMap: [KIRExprID: KIRExprID] = [:]
        let expectedID = Int32(arena.expressions.count)

        let cloned = InlineExprCloning.cloneOrReuseExpr(
            missingSource,
            localExprMap: &localExprMap,
            in: arena,
            substituteType: { _ in types.intType }
        )

        #expect(cloned.rawValue == expectedID)
        #expect(arena.expr(cloned) == .temporary(expectedID))
        #expect(arena.exprType(cloned) == types.intType)
    }
}
#endif
