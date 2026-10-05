@testable import CompilerCore
import Testing

@Suite
struct ExtensionCallablePropertyTests {
    @Test
    func memberPropertiesKeepDispatchAndExtensionReceiversSeparate() throws {
        let ctx = makeContextFromSource("""
        class D(private val convertTo: Int.() -> String, private val convert: String.() -> Int) {
            fun f(i: Int): String = i.convertTo()
            fun g(s: String): Int = s.convert()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let bindings = sema.bindings.callableValueCalls.values.filter { $0.extensionCallableExpr != nil }
        #expect(bindings.count == 2)
        for binding in bindings {
            let calleeExpr = try #require(binding.extensionCallableExpr)
            guard case .nameRef = ast.arena.expr(calleeExpr) else {
                Issue.record("Expected a lexical property read, not a read on Int/String")
                continue
            }
            let symbol = try #require(sema.bindings.identifierSymbol(for: calleeExpr))
            #expect(sema.symbols.symbol(symbol)?.kind == .property)
        }
        let module = try #require(ctx.kir)
        for name in ["f", "g"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("kk_function_invoke"))
            #expect(!callees.contains("convertTo"))
            #expect(!callees.contains("convert"))
        }
    }

    @Test
    func genericMemberPropertyInsideMapIsAccepted() throws {
        let ctx = makeContextFromSource("""
        class Converter<From, To>(private val convert: From.() -> To) {
            fun one(element: From): To = element.convert()
            fun all(elements: List<From>): List<To> = elements.map { it.convert() }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test
    func localParameterAndNullableReceiverFunctionValuesAreAccepted() throws {
        let ctx = makeContextFromSource("""
        fun local(i: Int, action: Int.(Int) -> Int): Int = i.action(2)
        fun nullable(s: String?, action: String?.() -> Int): Int = s.action()
        fun safe(s: String?, action: String.() -> Int): Int? = s?.action()
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test(arguments: [
        "fun bad(action: Int.() -> Int): Int = \"x\".action()",
        "fun bad(action: Int.(Int) -> Int): Int = 1.action()",
        "fun bad(action: Int.() -> Int): Int = 1.action(2)",
        "fun bad(action: Int.(Int) -> Int): Int = 1.action(\"x\")",
        "fun bad(action: (Int.() -> Int)?): Int = 1.action()",
        "fun bad(s: String?, action: String.() -> Int): Int = s.action()",
        "fun bad(action: Int.(Int) -> Int): Int = 1.action(value = 2)",
        "fun bad(action: Int.() -> Int): Int = 1.action<Int>()"
    ])
    func invalidReceiverFunctionValueCallsAreRejected(_ source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Invalid receiver-function invocation was accepted: \(source)")
    }
}
