@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CoroutineStartReceiverFunctionTypeTests {
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
