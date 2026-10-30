import Foundation
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableTypeParameterVarianceTests {
    private func check(_ source: String) throws -> CompilationContext {
        let input = "/virtual/callable-type-parameter-variance.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data(source.utf8))
        try runSema(context)
        return context
    }

    @Test(arguments: [
        "fun <in T> f(value: T): T = value",
        "fun <out T> f(): T? = null",
        "fun <A, out B> f(value: A): A = value",
        "class C { fun <in T> f(value: T): T = value }",
        "interface C { fun <out T> f(): T? }",
        "object C { fun <out T> f(): T? = null }",
        "class C { companion object { fun <out T> f(): T? = null } }",
        "fun outer() { fun <in T> local(value: T): T = value }",
        "fun outer() { fun <out T> local(): T? = null }",
        "fun outer() { class Local { fun <out T> f(): T? = null } }",
        "fun outer() { val value = object { fun <in T> f(value: T): T = value } }",
        "fun <out T> T.identity(): T = this",
        "inline fun <reified out T> f(value: T): T = value",
    ])
    func rejectsVarianceOnCallableTypeParameters(source: String) throws {
        let context = try check(source)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0443"
                && $0.message.contains("only allowed for type parameters of classes and interfaces")
        }, "\(source): \(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun <T> identity(value: T): T = value",
        "class Box<out T>(val value: T)",
        "interface Consumer<in T> { fun accept(value: T) }",
        "class Outer<out T>(val value: T) { fun <U> identity(value: U): U = value }",
        "class C { fun <T> identity(value: T): T = value }",
        "fun outer() { fun <T> local(value: T): T = value }",
        "class Box<T>(val value: T)\nval <T> Box<T>.same: T get() = value",
        "class Box<T>\nfun <T> use(value: Box<out T>) {}",
        "interface Sink<in T>\nfun <T, C : Sink<in T>> use(value: C): C = value",
        "inline fun <reified T> identity(value: T): T = value",
    ])
    func preservesValidVarianceAndInvariantCallables(source: String) throws {
        let context = try check(source)
        #expect(!context.diagnostics.hasError, "\(source): \(context.diagnostics.diagnostics)")
    }

    @Test
    func preservesExistingPropertyVarianceDiagnostic() throws {
        let context = try check("val <out T> T.identity: T get() = this")
        #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0005" })
        #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0443" })
    }
}
