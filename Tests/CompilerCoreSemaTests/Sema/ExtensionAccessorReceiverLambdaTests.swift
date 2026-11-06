#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

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

    // KUU-3914: an unqualified sibling extension property inside a
    // receiver-typed lambda binds to the enclosing extension receiver —
    // previously this was reported as KSWIFTK-SEMA-0022 unresolved reference
    // because extension-property lookup only considered the innermost
    // receiver-tower entry.
    @Test func siblingExtensionPropertyResolvesInsideReceiverLambda() throws {
        let ctx = makeContext("""
        class B(val host: String)
        class StringBuilder { fun append(value: String) {} }
        fun buildString(block: StringBuilder.() -> Unit): String {
            StringBuilder().block()
            return ""
        }
        val B.sibling: String get() = host
        val B.authority: String get() = buildString { append(sibling) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let sibling = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("sibling")
        ]).first(where: { sema.symbols.symbol($0)?.kind == .property }))
        #expect(sema.bindings.identifierSymbols.values.contains(sibling))
    }

    // KUU-4340: an unqualified generic extension property inside an extension
    // function on the same receiver type binds through the implicit-receiver
    // tower — the property's own type parameter is instantiated from the
    // receiver (`Box<V>` supplies `T := V`), matching the explicit
    // `this.content` getter result. Previously this was reported as
    // KSWIFTK-SEMA-0022 unresolved reference.
    @Test func genericExtensionPropertyResolvesInsideExtensionFunction() throws {
        let path = "/virtual/extension-accessor-receiver-lambda.kt"
        let ctx = makeContext("""
        class Box<V>(val stored: V) { fun get(): V = stored }
        val <T> Box<T>.content: T get() = get()
        fun <V> Box<V>.readGeneric(): V = content
        fun Box<Int>.readConcrete(): Int = content
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let contentName = ctx.interner.intern("content")
        let refs = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .nameRef(name, _) = expr else { return false }
            return name == contentName
        }
        #expect(refs.count == 2)
        let property = try #require(
            sema.symbols.lookupAll(fqName: [contentName])
                .first(where: { sema.symbols.symbol($0)?.kind == .property })
        )
        let readGeneric = try #require(
            sema.symbols.lookup(fqName: [ctx.interner.intern("readGeneric")])
        )
        let receiverTypeParam = try #require(
            sema.symbols.functionSignature(for: readGeneric)?.typeParameterSymbols.first
        )
        for (index, ref) in refs.enumerated() {
            #expect(sema.bindings.identifierSymbols[ref] == property)
            #expect(sema.bindings.implicitReceiverMemberNames[ref] == contentName)
            let type = try #require(sema.bindings.exprType(for: ref))
            #expect(type != sema.types.errorType)
            if index == 0 {
                // The generic read keeps the function's own `V`: the
                // property's `T` was substituted from the `Box<V>` receiver.
                guard case let .typeParam(param) = sema.types.kind(of: type) else {
                    Issue.record("Expected a type parameter, got \(sema.types.kind(of: type))")
                    continue
                }
                #expect(param.symbol == receiverTypeParam)
            } else {
                #expect(type == sema.types.intType)
            }
        }
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

    private func makeContext(_ source: String) -> CompilationContext {
        let path = "/virtual/extension-accessor-receiver-lambda.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
