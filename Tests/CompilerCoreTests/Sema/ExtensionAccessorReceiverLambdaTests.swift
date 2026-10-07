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

    private func makeContext(_ source: String) -> CompilationContext {
        let path = "/virtual/extension-accessor-receiver-lambda.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
