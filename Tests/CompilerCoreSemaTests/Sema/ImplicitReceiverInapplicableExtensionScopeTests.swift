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
}
#endif
