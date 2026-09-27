@testable import CompilerCore
import Testing

@Suite
struct ContinuationSourceContractTests {
    @Test
    func sourceContractRequiresResumeWithImplementation() throws {
        let source = """
        import kotlin.coroutines.*
        class Missing : Continuation<Int> {
            override val context = EmptyCoroutineContext
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" })
        }
    }

    @Test
    func sourceContractAcceptsBothMembersAndResumeExtensions() throws {
        let source = """
        import kotlin.coroutines.*
        class Complete : Continuation<Int> {
            override val context = EmptyCoroutineContext
            override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
        }
        fun probe(continuation: Continuation<Int>) {
            continuation.resume(7)
            continuation.resumeWithException(IllegalStateException("failed"))
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        }
    }
}
