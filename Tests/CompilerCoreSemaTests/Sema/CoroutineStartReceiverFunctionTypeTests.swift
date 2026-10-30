@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CoroutineStartReceiverFunctionTypeTests {
    /// KUU-3838: a `functionType` delegation specifier on an object literal
    /// (`object : suspend () -> T`) resolves to the nominal SuspendFunctionN /
    /// FunctionN interface — the `invoke` override binds and the literal is a
    /// subtype of the function type, so `startCoroutine` resolves on it.
    @Test
    func objectLiteralFunctionTypeSupertypeResolvesStartCoroutine() throws {
        let source = """
        interface Completion<T>

        fun <T> (suspend () -> T).startCoroutine(completion: Completion<T>) {}
        fun <R, T> (suspend R.() -> T).startCoroutine(receiver: R, completion: Completion<T>) {}

        fun main() {
            val o: suspend () -> Int = object : suspend () -> Int {
                override suspend fun invoke(): Int = 42
            }
            o.startCoroutine(object : Completion<Int> {})
            val p: suspend (String) -> Int = object : suspend (String) -> Int {
                override suspend fun invoke(value: String): Int = value.length
            }
            p.startCoroutine("arg", object : Completion<Int> {})
            val f: () -> Int = object : () -> Int {
                override fun invoke(): Int = 42
            }
            f()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    /// KUU-3319: a generic suspend receiver extension accepts the equivalent
    /// non-receiver function type with the receiver as its leading parameter.
    @Test
    func startCoroutineAcceptsSuspendFunctionWithReceiverArgument() throws {
        let source = """
        interface Completion<T>

        fun <R, T> (suspend R.() -> T).startCoroutine(receiver: R, completion: Completion<T>) {}

        fun launchFunctionType(block: suspend (String) -> Unit, completion: Completion<Unit>) {
            block.startCoroutine("", completion)
        }
        fun launchReceiverType(block: suspend String.() -> Unit, completion: Completion<Unit>) {
            block.startCoroutine("", completion)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }
}
