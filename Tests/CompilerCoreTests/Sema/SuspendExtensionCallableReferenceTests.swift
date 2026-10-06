#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SuspendExtensionCallableReferenceTests {
    @Test(arguments: [
        "runTest(testBody = TestScope::fnBody)",
        "runTest(context = kotlin.coroutines.EmptyCoroutineContext, testBody = TestScope::fnBody)",
        "val body: suspend TestScope.() -> Unit = TestScope::fnBody; runTest(testBody = body)",
        "val body = TestScope::fnBody; runTest(testBody = body)",
    ])
    func acceptsRunTestReference(body: String) throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.test.*
        @OptIn(ExperimentalCoroutinesApi::class)
        suspend fun TestScope.fnBody() {
            println(currentTime)
            advanceTimeBy(9)
        }
        @OptIn(ExperimentalCoroutinesApi::class)
        fun main() { \(body) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
    }

    @Test(arguments: [
        "consume(Scope::body)",
        "val ref: suspend Scope.() -> Unit = Scope::body; consume(ref)",
        "val ref = Scope::body; consume(ref)",
    ])
    func acceptsGenericExtensionReference(body: String) throws {
        let ctx = makeContextFromSource("""
        class Scope
        suspend fun <T> T.body() {}
        fun consume(body: suspend Scope.() -> Unit) {}
        fun main() { \(body) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
    }

    @Test(arguments: [false, true])
    func usesNamedParameterExpectedType(overloaded: Bool) throws {
        let other = overloaded
            ? "fun consume(before: Int, body: suspend Scope.() -> Unit) {}"
            : ""
        let ctx = makeContextFromSource("""
        class Scope
        suspend fun <T> T.body() {}
        fun consume(before: () -> Unit = {}, body: suspend Scope.() -> Unit) {}
        \(other)
        fun main() { consume(body = Scope::body) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
    }

    @Test(arguments: [
        "consume(::body)",
        "consume(Other::other)",
        "consume(Scope::withArgument)",
        "consume(Scope()::body)",
        "val ref: Scope.() -> Unit = Scope::body",
    ])
    func rejectsInvalidReference(body: String) throws {
        let ctx = makeContextFromSource("""
        class Scope
        class Other
        suspend fun Scope.body() {}
        suspend fun Other.other() {}
        suspend fun Scope.withArgument(value: Int) {}
        fun consume(body: suspend Scope.() -> Unit) {}
        fun main() { \(body) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
