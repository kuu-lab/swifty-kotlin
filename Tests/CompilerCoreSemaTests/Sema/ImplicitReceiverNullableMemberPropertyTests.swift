#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// KUU-4504: an unqualified member property read/write or callable-property
/// invoke inside a nullable implicit-receiver scope is unsafe — kotlinc
/// reports "only safe (?.) or non-null asserted (!!.) calls are allowed".
/// Such a member also loses to a same-named member on a non-null outer
/// receiver, and `Any` members stay reachable on the nullable receiver.
@Suite struct ImplicitReceiverNullableMemberPropertyTests {
    private func makeContext(_ source: String) -> (ctx: CompilationContext, path: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path])
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return (ctx, path)
    }

    @Test func nullableImplicitReceiverRejectsMemberPropertyRead() throws {
        let (ctx, _) = makeContext("""
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun viaNullableMemberProp(s: String?): Int = scopeOf(s) { length }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" })
    }

    @Test func nullableImplicitReceiverRejectsMemberPropertyWrites() throws {
        let (ctx, _) = makeContext("""
        class Box { var n: Int = 0; val ro: Int = 0 }
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun writeVar(b: Box?): Unit = scopeOf(b) { n = 1 }
        fun compoundVar(b: Box?): Unit = scopeOf(b) { n += 1 }
        fun writeVal(b: Box?): Unit = scopeOf(b) { ro = 1 }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        // kotlinc reports UNSAFE_CALL on all three writes plus a second
        // val-reassignment error on `ro = 1`.
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0026" }.count == 3, "\(errors)")
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0014" }, "\(errors)")
    }

    @Test func nullableImplicitReceiverDoesNotOfferCallablePropertyInvoke() throws {
        let (ctx, path) = makeContext("""
        class Handler { val run: () -> Int = { 1 } }
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun viaNullableCallableProperty(h: Handler?): Int = scopeOf(h) { run() }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "expected an unsafe-call rejection")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Handler"), ctx.interner.intern("run"),
        ]))
        let runCalleeIDs = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .nameRef(name, _) = expr else { return false }
            return ctx.interner.resolve(name) == "run"
        }
        // `run()` may fall through to a scope candidate (`kotlin.run`), but it
        // must never invoke the property through the nullable receiver.
        for callee in runCalleeIDs {
            #expect(sema.bindings.implicitReceiverMemberNames[callee] != ctx.interner.intern("run"))
            #expect(sema.bindings.identifierSymbol(for: callee) != property)
        }
    }

    /// A member on a nullable receiver is unsafe, so a same-named member on
    /// a non-null outer receiver still resolves — the unsafe inner member
    /// does not shadow it.
    @Test func nullableImplicitReceiverMemberYieldsToOuterSafeMember() throws {
        let (ctx, path) = makeContext("""
        class Outer { val length: Int = 99 }
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun outerShadow(s: String?, o: Outer): Int = scopeOf(o) { scopeOf(s) { length } }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let outer = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Outer"), ctx.interner.intern("length"),
        ]))
        let lengthRefIDs = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expr in
            guard case let .nameRef(name, _) = expr else { return false }
            return ctx.interner.resolve(name) == "length"
                && sema.bindings.exprType(for: exprID) != nil
        }
        #expect(lengthRefIDs.count == 1)
        let ref = try #require(lengthRefIDs.first)
        #expect(sema.bindings.identifierSymbol(for: ref) == outer)
    }

    /// The same precedence applies to callable properties: the unsafe inner
    /// `h.run` is skipped and the safe outer `o.run` is invoked.
    @Test func nullableImplicitReceiverCallablePropertyYieldsToOuterSafeMember() throws {
        let (ctx, path) = makeContext("""
        class Handler { val run: () -> Int = { 1 } }
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun outerCallable(h: Handler?, o: Handler): Int = scopeOf(o) { scopeOf(h) { run() } }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let runCallIDs = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expr in
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(name, _)? = ast.arena.expr(callee)
            else { return false }
            return ctx.interner.resolve(name) == "run"
                && sema.bindings.exprType(for: exprID) != nil
        }
        let call = try #require(runCallIDs.first)
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        guard case let .localValue(target) = binding.target else {
            Issue.record("Expected the callable property invoke target")
            return
        }
        // `run` resolves to the member through the outer non-null receiver.
        #expect(sema.symbols.symbol(target)?.name == ctx.interner.intern("run"))
    }

    /// `Any` members are callable on a nullable receiver: `toString` /
    /// `hashCode` / `equals` are declared on `Any?` and must keep resolving.
    @Test func nullableImplicitReceiverAnyMembersRemainCallable() throws {
        let (ctx, _) = makeContext("""
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun viaToString(s: String?): String = scopeOf(s) { toString() }
        fun viaHashCode(s: String?): Boolean = scopeOf(s) { hashCode() == hashCode() }
        fun viaEquals(s: String?): Boolean = scopeOf(s) { equals("x") }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
#endif
