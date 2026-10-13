@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct ContravariantContinuationConstraintTests {
    @Test(arguments: [false, true])
    func testBundledCancellableStartAcceptsAnyNullableCompletion(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.intrinsics.startCoroutineCancellable

        private val NO_CB = object : Continuation<Any?> {
            override val context: CoroutineContext get() = EmptyCoroutineContext
            override fun resumeWith(result: Result<Any?>) {}
        }
        internal fun <R> (suspend () -> R).ff() {
            this.startCoroutineCancellable(NO_CB)
        }
        fun <R> typed(block: suspend () -> R, completion: Continuation<Any?>) {
            block.startCoroutineCancellable(completion)
            block.startCoroutineCancellable<R>(completion)
        }
        fun <R> widened(completion: Continuation<Any?>): Continuation<R> = completion
        """
        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let context = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")
            let sema = try #require(context.sema)
            let callable = try #require(sema.symbols.lookup(fqName:
                ["kotlinx", "coroutines", "intrinsics", "startCoroutineCancellable"].map(context.interner.intern)
            ))
            #expect(sema.symbols.isSourceBackedSymbol(callable))
            #expect(sema.symbols.symbol(callable)?.flags.contains(.importedLibrary) == useLibrary)
        }
    }

    @Test(arguments: [false, true])
    func testBundledCancellableStartRejectsNarrowerCompletion(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.intrinsics.startCoroutineCancellable

        fun <R> generic(block: suspend () -> R, completion: Continuation<Int>) {
            block.startCoroutineCancellable(completion)
        }
        fun concrete(block: suspend () -> String, completion: Continuation<Int>) {
            block.startCoroutineCancellable<String>(completion)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let context = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 2, "\(errors.map { "\($0.code): \($0.message)" })")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" })
        }
    }
}
