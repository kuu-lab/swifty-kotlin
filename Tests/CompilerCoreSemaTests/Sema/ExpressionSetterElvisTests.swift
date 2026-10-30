@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpressionSetterElvisTests {
    @Test
    func genericSetterResolvesImplicitLambdaParameter() throws {
        let bodies = [
            "p?.let { stored = it } ?: run { flag = true }",
            "p?.let { stored = it; flag = false } ?: run { flag = true }",
            "p?.let { stored = it } ?: Unit",
            "p?.let { stored = it; flag = false } ?: Unit",
        ]
        var sources = bodies.enumerated().map { index, body in
            """
            class V\(index)<T : Any> {
                var stored: T? = null
                var flag = false
                var value: T?
                    get() = stored
                    set(p) = \(body)
            }
            """
        }
        sources.append("""
        fun <T : Any> f(p: T?): Unit = p?.let { println(it) } ?: run { println("null") }
        """)
        _ = try SemaFixture(surface: "expression setter Elvis").make(sources: sources)
    }
}
