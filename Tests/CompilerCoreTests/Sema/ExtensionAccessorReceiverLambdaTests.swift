#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ExtensionAccessorReceiverLambdaTests {
    @Test(arguments: [
        "val B.authority: String get() = buildString { append(host); append(port.toString()) }",
        "fun B.authority(): String = buildString { append(host); append(port.toString()) }",
        "var B.authority: String get() = host; set(value) { buildString { append(host); append(value) } }",
        "val B.authority: String get() = buildString { buildString { append(host) } }",
        "val B.authority: String get() = buildString { append(this@authority.host) }"
    ])
    func accessorRetainsExtensionReceiver(declaration: String) throws {
        let ctx = makeContext("""
        class B(val host: String, val port: Int)
        class StringBuilder { fun append(value: String) {} }
        fun buildString(block: StringBuilder.() -> Unit): String {
            StringBuilder().block()
            return ""
        }
        \(declaration)
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test func innerReceiverMemberKeepsPrecedence() throws {
        let ctx = makeContext("""
        class B(val host: String)
        class Scope(val host: Int)
        fun scoped(block: Scope.() -> Int): Int = Scope(42).block()
        val B.authority: Int get() = scoped { host }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let innerProperty = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("Scope"), ctx.interner.intern("host")
        ]))
        #expect(sema.bindings.identifierSymbols.values.contains(innerProperty))
    }

    @Test
    func labeledAnonymousExtensionFunctionCanAddressBothReceivers() throws {
        let ctx = makeContext("""
        class A(val x: String)
        val <T> T.a: T.() -> String
            get() = fun1@ fun T.(): String { return (this@fun1 as A).x + (this@a as A).x }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        guard !ctx.diagnostics.hasError else { return }

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let anonymousFunction = try #require(ast.arena.exprs.indices.first { index in
            guard case let .localFunDecl(name, _, _, _, _, _, _, _, _) = ast.arena.exprs[index] else {
                return false
            }
            return name == ctx.interner.intern("fun1")
        })
        let anonymousFunctionSymbol = try #require(sema.bindings.identifierSymbol(
            for: ExprID(rawValue: Int32(anonymousFunction))
        ))
        let propertySymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("a")]))
        let receiverReferences = ast.arena.exprs.enumerated().compactMap { entry -> (InternedString, SymbolID?)? in
            let (index, expression) = entry
            guard case let .thisRef(label?, _) = expression else { return nil }
            guard label == ctx.interner.intern("fun1") || label == ctx.interner.intern("a") else { return nil }
            return (label, sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(index))))
        }
        #expect(receiverReferences.count == 2, "Expected both qualified receiver references: \(receiverReferences)")
        #expect(receiverReferences.first { $0.0 == ctx.interner.intern("fun1") }?.1 ==
            SyntheticSymbolScheme.receiverParameterSymbol(for: anonymousFunctionSymbol))
        #expect(receiverReferences.first { $0.0 == ctx.interner.intern("a") }?.1 ==
            SyntheticSymbolScheme.receiverParameterSymbol(for: propertySymbol))
    }

    private func makeContext(_ source: String) -> CompilationContext {
        let path = "/virtual/extension-accessor-receiver-lambda.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
