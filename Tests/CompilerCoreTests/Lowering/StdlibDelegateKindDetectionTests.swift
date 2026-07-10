#if canImport(Testing)
@testable import CompilerCore
import Testing

/// `StdlibDelegateKind.detect` is the single source of truth both KIR lowering
/// (`MemberLowerer`) and Sema (`DeclTypeChecker.typeCheckDelegate`) rely on to
/// recognize the stdlib delegate factories. These cases pin down the exact,
/// per-AST-node-shape matching rules so a future change can't silently make
/// one caller more (or less) permissive than the other.
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
        // Unlike `lazy`, `Delegates.observable` is never referenced as a bare
        // identifier — a bare `observable` name must not be exempted.
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
        // A user-defined member function that merely happens to be named
        // "lazy" (e.g. `someObject.lazy()`) is not the stdlib factory.
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
        // `foo.lazy()` wrapped in an extra call node must still not match
        // `lazy` — only member calls named observable/vetoable/notNull do.
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
