#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct AnonymousObjectInapplicableOuterMemberTests {
    @Test
    func stdlibRunHasCallBindingInsideObjectMember() throws {
        let source = """
        interface Delegate { fun invoke() }
        class Token(val value: Int)
        class Probe {
         fun run() {
          val first = Token(1)
          val second = Token(2)
          fun consume() {
           println(first.value)
           val delegate = object : Delegate {
            override fun invoke() {
             run { println(first.value); println(second.value) }
            }
           }
           delegate.invoke()
          }
          consume()
         }
        }
        fun main() { Probe().run() }
        """
        let declarations = """
        package kotlin
        fun <R> run(block: () -> R): R = block()
        fun <T, R> T.run(block: T.() -> R): R = block()
        fun println(value: Int) {}
        """
        try withTemporaryFiles(contents: [source, declarations]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "run", in: ast, interner: ctx.interner))
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            #expect(sema.symbols.symbol(chosen)?.fqName.map(ctx.interner.resolve) == ["kotlin", "run"])
        }
    }

    @Test(arguments: ["run", "choose"])
    func inapplicableOuterMemberDoesNotHideTopLevelFunction(_ name: String) throws {
        let source = """
        fun \(name)(block: () -> Unit) { block() }
        class Probe {
            fun \(name)() {
                fun consume() {
                    val delegate = object {
                        fun invoke() { \(name) { } }
                    }
                    delegate.invoke()
                }
                consume()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let topLevel = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(name)]))
            #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == topLevel })
        }
    }
}
#endif
