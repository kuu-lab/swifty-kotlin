#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-3919: an in-scope package extension on the implicit receiver whose
/// arguments cannot satisfy the call must not hide the next lexical/import
/// tier. `serializer(it)` inside `fun TypeInfo.serializer()` fell through to
/// `KSWIFTK-SEMA-0002` because the zero-parameter `TypeInfo.serializer`
/// extension ended candidate collection before the top-level
/// `serializer(KType)` could be seen. An *applicable* same-name extension
/// keeps Kotlin's extension-tier precedence over the top-level overload.
@Suite
struct ImplicitReceiverInapplicableExtensionScopeTests {
    private func callableSymbol(
        named name: String,
        receiver: Bool,
        in ctx: CompilationContext
    ) throws -> SymbolID {
        let sema = try #require(ctx.sema)
        let all = sema.symbols.lookupAll(fqName: [ctx.interner.intern(name)])
        return try #require(all.first {
            (sema.symbols.functionSignature(for: $0)?.receiverType != nil) == receiver
        })
    }

    @Test
    func inapplicableReceiverExtensionYieldsToTopLevelOverload() throws {
        let source = """
        class KType
        class TypeInfo(val kotlinType: KType)
        fun TypeInfo.serializer() {}
        fun serializer(type: KType): KType = type
        fun TypeInfo.probe(): KType = serializer(kotlinType)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "serializer", in: ast, interner: ctx.interner))
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let topLevel = try callableSymbol(named: "serializer", receiver: false, in: ctx)
            #expect(chosen == topLevel)
        }
    }

    @Test
    func applicableReceiverExtensionKeepsPrecedenceOverTopLevel() throws {
        let source = """
        class KType
        class TypeInfo(val kotlinType: KType)
        fun TypeInfo.serializer(type: KType): KType = type
        fun serializer(type: KType): Int = 0
        fun TypeInfo.probe(): KType = serializer(kotlinType)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "serializer", in: ast, interner: ctx.interner))
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let extension_ = try callableSymbol(named: "serializer", receiver: true, in: ctx)
            #expect(chosen == extension_)
        }
    }

    /// KUU-4271: an unqualified `invoke(element)` inside an extension on a
    /// function type (or a typealias of one, like kotlinx-coroutines'
    /// `OnUndeliveredElement<E> = (E) -> Unit`) is `this.invoke(element)`.
    /// An in-scope `invoke` extension on an unrelated receiver
    /// (`CoroutineDispatcher.invoke` in upstream) must not turn that into
    /// `KSWIFTK-SEMA-0002` — function types expose no nominal members for
    /// the ordinary implicit-receiver recovery paths.
    @Test
    func inapplicableInvokeExtensionYieldsToFunctionTypeReceiverInvoke() throws {
        let source = """
        class Dispatcher
        operator fun <T> Dispatcher.invoke(block: () -> T): T = block()
        typealias OnUndeliveredElement<E> = (E) -> Unit
        fun <E> OnUndeliveredElement<E>.callIt(element: E) {
            invoke(element)
        }
        fun use(handler: OnUndeliveredElement<String>) {
            handler.callIt("x")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.unitType)
        }
    }

    /// KUU-4093: inside an extension body, a receiver lambda's own members
    /// must win over a same-named scope extension that only matches an outer
    /// tower entry. `callImplicitReceiverType` was picked from the scope
    /// candidates (the `Recv.indexOf` extension matching the `Recv`
    /// extension receiver), so the lambda body's `Idx.indexOf` member was
    /// checked against `Recv` and rejected with SEMA-0002.
    @Test
    func lambdaReceiverMemberBeatsOuterReceiverScopeExtension() throws {
        let source = """
        class Recv
        class Idx { fun indexOf(s: String): Int = 0 }
        fun <R> withIdx(block: Idx.() -> R): R = Idx().block()
        fun Recv.indexOf(s: String): String = "outer"
        fun Recv.probe(): Int = withIdx { indexOf("x") }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try runToKIR(ctx)
            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let callees = findAllKIRFunctions(in: module).flatMap(\.body).compactMap { instruction -> SymbolID? in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "indexOf"
                else { return nil }
                return symbol
            }
            let chosen = try #require(callees.first)
            let chosenSymbol = try #require(sema.symbols.symbol(chosen))
            #expect(chosenSymbol.fqName == [ctx.interner.intern("Idx"), ctx.interner.intern("indexOf")])
        }
    }
}
#endif
