#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct DefaultArgumentExpectedTypeInferenceTests {
    @Test func usesEnclosingTypeParameterAsExpectedType() throws {
        let ctx = makeContextFromSource("""
        class G<T, R>(val t: T, val r: R? = null)
        class W<T>(val g: G<T, T>)
        fun <T, R> create(t: T, r: R? = null): G<T, R> = G(t, r)
        fun <T> wrap(g: G<T, T>): W<T> = W(g)
        fun <T : Any> ctor(t: T): W<T> = W(G(t))
        fun <T : Any> named(t: T): W<T> = W(g = G(t = t))
        fun <T : Any> factory(t: T): W<T> = W(create(t))
        fun <T : Any> function(t: T): W<T> = wrap(G(t))
        fun <T : Any> both(t: T): W<T> = wrap(create(t))
        fun <T : Any> directCtor(t: T): G<T, T> = G(t)
        fun <T : Any> directFunction(t: T): G<T, T> = create(t)
        fun <T> nullable(t: T): W<T> = W(G(t))
        fun concrete(): W<String> = W(G("ok"))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: ["W(G<T, String>(t))", "W(G(t, \"wrong\"))"])
    func preservesIncompatibleTypeArguments(expression: String) throws {
        let ctx = makeContextFromSource("""
        class G<T, R>(val t: T, val r: R? = null)
        class W<T>(val g: G<T, T>)
        fun <T : Any> make(t: T): W<T> = \(expression)
        """)
        try runSema(ctx)
        let hasError = ctx.diagnostics.hasError
        #expect(hasError, "Expected an incompatible type argument")
    }

    @Test func missingExpectedTypeRemainsUninferred() throws {
        let ctx = makeContextFromSource("""
        class G<T, R>(val t: T, val r: R? = null)
        fun <T : Any> make(t: T) { val result = G(t) }
        """)
        try runSema(ctx)
        let codes = ctx.diagnostics.diagnostics.map(\.code)
        #expect(codes.contains("KSWIFTK-SEMA-INFER"))
    }
}
#endif
