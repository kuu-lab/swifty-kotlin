#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct StdlibDelegateKindDetectionTests {
    private func module(_ arena: ASTArena) -> ASTModule {
        ASTModule(files: [], arena: arena, declarationCount: 0, tokenCount: 0)
    }

    private func detect(_ exprID: ExprID?, arena: ASTArena, interner: StringInterner) -> StdlibDelegateKind {
        StdlibDelegateKind.detect(delegateExpr: exprID, ast: module(arena), interner: interner)
    }

    @Test func testNilDelegateExprIsCustom() {
        let interner = StringInterner()
        #expect(StdlibDelegateKind.detect(delegateExpr: nil, ast: module(ASTArena()), interner: interner) == .custom)
    }

    @Test func testBareNameRefLazyIsLazy() {
        let arena = ASTArena()
        let interner = StringInterner()
        let exprID = arena.appendExpr(.nameRef(interner.intern("lazy"), makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .lazy)
    }

    @Test func testBareNameRefObservableIsCustomNotObservable() {
        let arena = ASTArena()
        let interner = StringInterner()
        let exprID = arena.appendExpr(.nameRef(interner.intern("observable"), makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .custom)
    }

    @Test func testBareNameRefUnrelatedIsCustom() {
        let arena = ASTArena()
        let interner = StringInterner()
        let exprID = arena.appendExpr(.nameRef(interner.intern("someVariable"), makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .custom)
    }

    @Test func testMemberCallObservableIsObservable() {
        let arena = ASTArena()
        let interner = StringInterner()
        let receiver = arena.appendExpr(.nameRef(interner.intern("Delegates"), makeRange()))
        let exprID = arena.appendExpr(.memberCall(
            receiver: receiver, callee: interner.intern("observable"), typeArgs: [], args: [], range: makeRange()
        ))
        #expect(detect(exprID, arena: arena, interner: interner) == .observable)
    }

    @Test func testMemberCallVetoableIsVetoable() {
        let arena = ASTArena()
        let interner = StringInterner()
        let receiver = arena.appendExpr(.nameRef(interner.intern("Delegates"), makeRange()))
        let exprID = arena.appendExpr(.memberCall(
            receiver: receiver, callee: interner.intern("vetoable"), typeArgs: [], args: [], range: makeRange()
        ))
        #expect(detect(exprID, arena: arena, interner: interner) == .vetoable)
    }

    @Test func testMemberCallNotNullIsNotNull() {
        let arena = ASTArena()
        let interner = StringInterner()
        let receiver = arena.appendExpr(.nameRef(interner.intern("Delegates"), makeRange()))
        let exprID = arena.appendExpr(.memberCall(
            receiver: receiver, callee: interner.intern("notNull"), typeArgs: [], args: [], range: makeRange()
        ))
        #expect(detect(exprID, arena: arena, interner: interner) == .notNull)
    }

    @Test func testMemberCallNamedLazyIsCustomNotLazy() {
        let arena = ASTArena()
        let interner = StringInterner()
        let receiver = arena.appendExpr(.nameRef(interner.intern("someObject"), makeRange()))
        let exprID = arena.appendExpr(.memberCall(
            receiver: receiver, callee: interner.intern("lazy"), typeArgs: [], args: [], range: makeRange()
        ))
        #expect(detect(exprID, arena: arena, interner: interner) == .custom)
    }

    @Test func testCallOfNameRefLazyIsLazy() {
        let arena = ASTArena()
        let interner = StringInterner()
        let callee = arena.appendExpr(.nameRef(interner.intern("lazy"), makeRange()))
        let exprID = arena.appendExpr(.call(callee: callee, typeArgs: [], args: [], range: makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .lazy)
    }

    @Test func testCallOfNameRefObservableIsObservable() {
        let arena = ASTArena()
        let interner = StringInterner()
        let callee = arena.appendExpr(.nameRef(interner.intern("observable"), makeRange()))
        let exprID = arena.appendExpr(.call(callee: callee, typeArgs: [], args: [], range: makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .observable)
    }

    @Test func testCallOfMemberCallVetoableIsVetoable() {
        let arena = ASTArena()
        let interner = StringInterner()
        let receiver = arena.appendExpr(.nameRef(interner.intern("Delegates"), makeRange()))
        let callee = arena.appendExpr(.memberCall(
            receiver: receiver, callee: interner.intern("vetoable"), typeArgs: [], args: [], range: makeRange()
        ))
        let exprID = arena.appendExpr(.call(callee: callee, typeArgs: [], args: [], range: makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .vetoable)
    }

    @Test func testCallOfMemberCallNamedLazyIsCustomNotLazy() {
        let arena = ASTArena()
        let interner = StringInterner()
        let receiver = arena.appendExpr(.nameRef(interner.intern("someObject"), makeRange()))
        let callee = arena.appendExpr(.memberCall(
            receiver: receiver, callee: interner.intern("lazy"), typeArgs: [], args: [], range: makeRange()
        ))
        let exprID = arena.appendExpr(.call(callee: callee, typeArgs: [], args: [], range: makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .custom)
    }

    @Test func testCallOfNameRefUnrelatedIsCustom() {
        let arena = ASTArena()
        let interner = StringInterner()
        let callee = arena.appendExpr(.nameRef(interner.intern("someFactory"), makeRange()))
        let exprID = arena.appendExpr(.call(callee: callee, typeArgs: [], args: [], range: makeRange()))
        #expect(detect(exprID, arena: arena, interner: interner) == .custom)
    }
}
#endif
