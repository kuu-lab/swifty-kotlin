#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ImplicitReceiverCallablePropertyInvocationTests {
    private func makeIsolatedContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func memberFunctionPropertyCallsThroughImplicitReceiver() throws {
        let ctx = makeIsolatedContext("""
        class Holder(val f: (Int) -> String) {
            fun method(value: Int): String = "member:$value"
        }
        fun Holder.read(): String {
            val local = f
            return f(3) + local(3) + method(3)
        }
        fun explicit(holder: Holder): String = holder.f(3)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "f", in: ast, interner: ctx.interner))
        guard case let .call(callee, _, _, _) = ast.arena.expr(call) else {
            Issue.record("Expected an unqualified property call")
            return
        }
        let property = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Holder"), ctx.interner.intern("f"),
        ]))
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        #expect(binding.target == .localValue(property))
        #expect(binding.receiverArgumentOffset == 0)
        #expect(sema.bindings.identifierSymbol(for: callee) == property)
        #expect(sema.bindings.implicitReceiverMemberNames[callee] == ctx.interner.intern("f"))
    }

    @Test func receiverFunctionPropertyAcceptsItsReceiverArgument() throws {
        let ctx = makeIsolatedContext("""
        class Holder(val f: Int.() -> Int)
        fun Holder.read(): Int = f(4)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "f", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        #expect(binding.receiverArgumentOffset == 1)
        #expect(binding.parameterMapping == [:])
    }

    @Test func capturedReceiverFunctionParameterWinsOverMemberExtension() throws {
        let ctx = makeIsolatedContext("""
        interface Ctx { val y: String }
        interface Codec<T> { fun Ctx.decode(): T? }
        fun <T> codec(decode: Ctx.() -> T?): Codec<T> = object : Codec<T> {
            override fun Ctx.decode(): T? = decode()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "decode", in: ast, interner: ctx.interner))
        let codec = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("codec")]))
        let parameter = try #require(sema.symbols.functionSignature(for: codec)?.valueParameterSymbols.first)
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        #expect(binding.target == .localValue(parameter))
        #expect(sema.bindings.callBinding(for: call) == nil)

        let objectDeclID = try #require(ast.arena.exprs.compactMap { expression -> DeclID? in
            guard case let .objectLiteral(_, declID, _) = expression else { return nil }
            return declID
        }.first)
        guard case let .objectDecl(objectDecl)? = ast.arena.decl(objectDeclID) else {
            Issue.record("Expected an anonymous object declaration")
            return
        }
        let overrideDeclID = try #require(objectDecl.memberFunctions.first)
        let override = try #require(sema.bindings.declSymbols[overrideDeclID])
        let object = try #require(sema.bindings.declSymbols[objectDeclID])
        let interfaceMethod = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Codec"), ctx.interner.intern("decode"),
        ]))
        #expect(sema.symbols.memberExtensionOwnerSymbol(for: override) == object)
        #expect(kirFindOverrideMethod(
            for: interfaceMethod,
            in: object,
            sema: sema,
            interner: ctx.interner
        ) == override)
    }

    // KUU-4347: an implicit receiver's member callable property sits on a
    // nearer call-tower level than package/import scope functions, so
    // `apply()` binds the property — not `kotlin.apply`-style extensions —
    // even when the scope candidate resolves.
    @Test func implicitReceiverCallablePropertyBeatsScopeFunction() throws {
        let ctx = makeIsolatedContext("""
        class Outer {
            val apply: () -> Int = { 7 }
            fun test(): Int = apply()
        }
        fun <T> T.apply(block: T.() -> Unit): T = this
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "apply", in: ast, interner: ctx.interner))
        let property = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Outer"), ctx.interner.intern("apply"),
        ]))
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        #expect(binding.target == .localValue(property))
    }

    @Test func implicitReceiverCallablePropertyBeatsScopeFunctionInLambda() throws {
        let ctx = makeIsolatedContext("""
        class Outer { val apply: () -> Int = { 7 } }
        fun <T> T.apply(block: T.() -> Unit): T = this
        fun <T, R> with(receiver: T, block: T.() -> R): R = receiver.block()
        fun main() {
            val r = with(Outer()) { apply() }
            val check: Int = r
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        // Lambda arguments can leave an unbound probe copy of the call in the
        // arena; pick the instance that was actually checked.
        let applyCallIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .call(calleeExprID, _, _, _) = ast.arena.exprs[index],
                  case let .nameRef(calleeName, _)? = ast.arena.expr(calleeExprID),
                  ctx.interner.resolve(calleeName) == "apply",
                  sema.bindings.exprType(for: id) != nil
            else { return nil }
            return id
        }
        let call = try #require(applyCallIDs.first)
        let property = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Outer"), ctx.interner.intern("apply"),
        ]))
        let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
        #expect(binding.target == .localValue(property))
    }

    @Test func nearerLocalFunctionStillBeatsImplicitReceiverCallableProperty() throws {
        let ctx = makeIsolatedContext("""
        class Outer { val apply: () -> Int = { 7 } }
        fun <T> T.apply(block: T.() -> Unit): T = this
        fun <T, R> with(receiver: T, block: T.() -> R): R = receiver.block()
        fun main() {
            fun apply(): String = "local"
            val r = with(Outer()) { apply() }
            val check: String = r
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let applyCallIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .call(calleeExprID, _, _, _) = ast.arena.exprs[index],
                  case let .nameRef(calleeName, _)? = ast.arena.expr(calleeExprID),
                  ctx.interner.resolve(calleeName) == "apply",
                  sema.bindings.exprType(for: id) != nil
            else { return nil }
            return id
        }
        let call = try #require(applyCallIDs.first)
        #expect(sema.bindings.callableValueCallBinding(for: call) == nil)
        #expect(sema.bindings.callBinding(for: call) != nil)
    }
}
#endif
