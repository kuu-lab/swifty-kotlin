#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct GenericFunInterfaceParameterLambdaInferenceTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test
    func lambdaBodyInfersGenericSamReturnType() throws {
        let ctx = context("""
        fun interface IFoo<T> { fun foo(): T }
        var state = ""
        fun <T> consume(foo: IFoo<T>) { foo.foo() }
        fun box(): String {
            consume { state = "OK" }
            return state
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected the lambda body to infer IFoo<Unit>: \(errors)")

        let sema = try #require(ctx.sema)
        let lambda = try #require(sema.bindings.samConversionExprs.first)
        let interfaceType = try #require(sema.bindings.samInterfaceType(for: lambda))
        guard case let .classType(interface) = sema.types.kind(of: interfaceType) else {
            Issue.record("Expected the lambda to retain its SAM interface type")
            return
        }
        #expect(interface.args == [.invariant(sema.types.unitType)])
    }

    @Test(arguments: ["make", "Factory.make"])
    func annotatedSamInputInfersGenericFactoryResult(factory: String) throws {
        let ctx = context("""
        fun interface Key<T> { fun read(value: T): Int }
        class Holder<T>
        class Item(val value: Int)
        fun <T> make(key: Key<in T>): Holder<T> = Holder<T>()
        object Factory { fun <T> make(key: Key<in T>): Holder<T> = Holder<T>() }
        fun test() {
            val inferred = \(factory) { item: Item -> item.value }
            val exact: Holder<Item> = inferred
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "The annotated SAM input must infer Holder<Item>: \(errors)")
    }

    @Test(arguments: [
        "Factory.make<Item> { value: String -> 1 }",
        "Factory.bounded<Int> { value: Int -> value }",
        "Factory.make(Other<Item> { value: Item -> 1 })",
    ])
    func annotatedSamInputRetainsConcreteTypesAndBounds(call: String) throws {
        let ctx = context("""
        interface Marker
        class Item: Marker
        fun interface Key<T> { fun read(value: T): Int }
        fun interface Other<T> { fun read(value: T): Int }
        class Holder<T>
        object Factory {
            fun <T> make(key: Key<in T>): Holder<T> = Holder<T>()
            fun <T: Marker> bounded(key: Key<in T>): Holder<T> = Holder<T>()
        }
        fun invalid() { \(call) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Typed SAM inputs must preserve explicit arguments and bounds")
    }

    @Test
    func explicitGenericSamArgumentStillChecksLambdaResult() throws {
        let ctx = context("""
        fun interface IFoo<T> { fun foo(): T }
        fun <T> consume(foo: IFoo<T>) {}
        fun invalid() { consume<String> { 42 } }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "An Int result must not satisfy IFoo<String>")
    }

    @Test
    func inferredGenericSamArgumentStillChecksTypeParameterBounds() throws {
        let ctx = context("""
        interface Marker
        fun interface IFoo<T> { fun foo(): T }
        fun <T : Marker> consume(foo: IFoo<T>) {}
        fun invalid() { consume { 42 } }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError, "Int must not satisfy the Marker bound")
    }
}
#endif
