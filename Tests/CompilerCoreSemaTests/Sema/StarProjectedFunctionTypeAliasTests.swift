@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct StarProjectedFunctionTypeAliasTests {
    @Test
    func starProjectedFunctionAliasAcceptsEveryFunctionOfTheAlias() throws {
        let ctx = try semaContext(from: """
        typealias Handler<T> = (T) -> Unit
        typealias Extension<T> = T.() -> Unit
        typealias Producer<T> = () -> T

        class Registration(val handler: Handler<*>)

        fun <T> register(handler: Handler<T>): Registration = Registration(handler)
        fun registerString(handler: (String) -> Unit): Registration = Registration(handler)
        fun extension(block: Int.() -> Unit): Extension<*> = block
        fun produce(block: () -> String): Producer<*> = block
        fun keep(handlers: List<Handler<*>>, handler: (Long) -> Unit): List<Handler<*>> = handlers + handler
        """)
        #expect(ctx.errorDiagnostics.isEmpty, "\(ctx.errorDiagnostics)")
    }
}
