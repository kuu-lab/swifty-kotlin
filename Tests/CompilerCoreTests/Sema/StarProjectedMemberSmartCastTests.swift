#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct StarProjectedMemberSmartCastTests {
    @Test func boundedCopyableProperty() throws {
        let functions = ["origin", "this.origin"].enumerated().flatMap { subjectIndex, subject in
            ["origin", "this.origin"].enumerated().map { accessIndex, access in
                """
                fun Holder.check\(subjectIndex)\(accessIndex)(): Throwable? = when (\(subject)) {
                    null -> null
                    is Copyable<*> -> \(access).createCopy()
                    else -> origin
                }
                """
            }
        }.joined(separator: "\n")
        let ctx = makeContextFromSource("""
        interface Copyable<T : Throwable> { fun createCopy(): T? }
        class Holder(val origin: Throwable?)
        \(functions)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = ast.arena.exprs.indices.map { ExprID(rawValue: Int32($0)) }.filter { id in
            guard let expr = ast.arena.expr(id) else { return false }
            guard case let .memberCall(_, name, _, _, _) = expr else { return false }
            return ctx.interner.resolve(name) == "createCopy"
        }
        #expect(calls.count == 4)
        let throwableType = try #require(TypeCheckHelpers().throwableType(sema: sema, interner: ctx.interner))
        for call in calls {
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee != nil)
            let resultType = try #require(sema.bindings.exprType(for: call))
            #expect(sema.types.isSubtype(resultType, sema.types.makeNullable(throwableType)))
        }
    }

    @Test func unboundedCopyableLocal() throws {
        let ctx = makeContextFromSource("""
        interface Copyable<T> { fun createCopy(): T? }
        fun check(origin: Any?): Any? = when (origin) {
            null -> null
            is Copyable<*> -> origin.createCopy()
            else -> origin
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func unboundedCopyablePropertyReturnsAny() throws {
        let ctx = makeContextFromSource("""
        interface Copyable<T> { fun createCopy(): T? }
        class Holder(val origin: Any?)
        fun Holder.check(): Any? = when (origin) {
            null -> null
            is Copyable<*> -> origin.createCopy()
            else -> origin
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, name, _, _, _) = expr else { return false }
            return ctx.interner.resolve(name) == "createCopy"
        })
        #expect(sema.bindings.exprType(for: call) == sema.types.nullableAnyType)
    }

    @Test func narrowingDoesNotLeakToAnotherReceiverOrLocal() throws {
        let ctx = makeContextFromSource("""
        interface Copyable<T> { fun createCopy(): T? }
        class Holder(val origin: Any?)
        fun Holder.check(other: Holder): Any? = when (origin) {
            is Copyable<*> -> {
                other.origin.createCopy()
                val origin: Any = 1
                origin.createCopy()
            }
            else -> origin
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0024" }.count == 2)
    }

    @Test func unboundedCopyableDoesNotBecomeThrowable() throws {
        let ctx = makeContextFromSource("""
        interface Copyable<T> { fun createCopy(): T? }
        class Holder(val origin: Throwable?)
        fun Holder.check(): Throwable? = when (origin) {
            null -> null
            is Copyable<*> -> origin.createCopy()
            else -> origin
        }
        """)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    // KUU-1371: `x != null && x is List<*>` narrows a type-parameter member
    // property `R?` to the intersection `R & List<*>`; extension member calls
    // on the receiver must resolve against the `List` part.
    @Test func typeParameterPropertyNarrowsToIntersectionAndResolvesExtension() throws {
        let ctx = makeContextFromSource("""
        class D<R>(val defaultValue: R?)
        fun <R> check(d: D<R>): Boolean =
            d.defaultValue != null && (d.defaultValue is List<*> && d.defaultValue.isNotEmpty() || d.defaultValue !is List<*>)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(memberCallExprIDs(
            named: "isNotEmpty",
            in: ast,
            path: ctx.options.inputs[0],
            ctx: ctx,
            interner: ctx.interner
        ).first)
        #expect(sema.bindings.callBinding(for: call)?.chosenCallee != nil)
        #expect(sema.bindings.exprType(for: call) == sema.types.booleanType)
        guard case let .memberCall(receiverID, _, _, _, _) = ast.arena.expr(call),
              let receiverType = sema.bindings.exprType(for: receiverID),
              case let .intersection(parts) = sema.types.kind(of: receiverType)
        else {
            Issue.record("expected intersection-narrowed receiver for isNotEmpty()")
            return
        }
        #expect(parts.contains { part in
            guard case let .classType(classType) = sema.types.kind(of: part),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else { return false }
            return symbol.fqName.last == ctx.interner.intern("List")
        })
    }

    @Test(arguments: [
        "class Holder(var origin: Any?)",
        "class Holder { val origin: Any? get() = null }"
    ])
    func unstableImplicitPropertyIsNotNarrowed(declaration: String) throws {
        let ctx = makeContextFromSource("""
        interface Copyable<T> { fun createCopy(): T? }
        \(declaration)
        fun Holder.check(): Any? = when (origin) {
            is Copyable<*> -> origin.createCopy()
            else -> origin
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }
}
#endif
