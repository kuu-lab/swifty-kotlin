#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImplicitAnyMemberCallResolutionTests {
    // KUU-2939: a bare `toString()` inside an extension is an implicit
    // receiver call whose member lookup used to start from the receiver's
    // nominal symbols. Builtin kinds (`.any`, `.stringStruct`, primitives)
    // and type parameters returned no roots, so kotlin.Any members were
    // unreachable and the call failed with KSWIFTK-SEMA-0002.
    @Test func implicitToStringResolvesToKotlinAnyOnBuiltinReceivers() throws {
        let ctx = try semaContext(for: ["""
        fun <T> T.onT(): String = toString()
        fun <T : Any> T.onTBounded(): String = toString()
        fun Any.onAny(): String = toString()
        fun Any?.onAnyNullable(): String = toString()
        fun String.onString(): String = toString()
        fun Int.onInt(): String = toString()
        fun Char.onChar(): String = toString()
        fun Boolean.onBool(): String = toString()
        """])
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map(\.message))")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let toStringName = ctx.interner.intern("toString")
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(exprID, in: ctx),
                  let expr = ast.arena.expr(exprID),
                  case let .call(callee, _, args, _) = expr,
                  args.isEmpty,
                  let calleeExpr = ast.arena.expr(callee),
                  case let .nameRef(name, _) = calleeExpr,
                  name == toStringName
            else {
                return nil
            }
            return exprID
        }
        #expect(calls.count == 8)
        for call in calls {
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let fqName = sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) }
            #expect(fqName == ["kotlin", "Any", "toString"])
        }
    }

    // The kotlin.Any fallback must not shadow a more derived member: a class
    // that overrides toString still binds the implicit call to itself.
    @Test func implicitToStringPrefersUserOverrideOverAnyFallback() throws {
        let ctx = try semaContext(for: ["""
        class User(val tag: String) {
            override fun toString(): String = tag
            fun render(): String = toString()
        }
        """])
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map(\.message))")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let toStringName = ctx.interner.intern("toString")
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(exprID, in: ctx),
                  let expr = ast.arena.expr(exprID),
                  case let .call(callee, _, args, _) = expr,
                  args.isEmpty,
                  let calleeExpr = ast.arena.expr(callee),
                  case let .nameRef(name, _) = calleeExpr,
                  name == toStringName
            else {
                return nil
            }
            return exprID
        }
        let call = try #require(calls.first)
        #expect(calls.count == 1)
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        let owner = try #require(sema.symbols.parentSymbol(for: chosen))
        let ownerName = try #require(sema.symbols.symbol(owner)?.name)
        #expect(ctx.interner.resolve(ownerName) == "User")
    }
}
#endif
