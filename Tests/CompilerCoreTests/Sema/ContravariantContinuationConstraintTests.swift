@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct ContravariantContinuationConstraintTests {
    @Test(arguments: [false, true])
    func testBundledCancellableStartAcceptsAnyNullableCompletion(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let calls = """
        internal fun <R> (suspend () -> R).ff() {
            this.startCoroutineCancellable(NO_CB)
            this.startCoroutineCancellable<R>(NO_CB)
        }
        fun <R> typed(block: suspend () -> R, completion: Continuation<Any?>) {
            block.startCoroutineCancellable(completion)
            block.startCoroutineCancellable<R>(completion)
        }
        fun <R> widened(completion: Continuation<Any?>): Continuation<R> = completion
        """
        // Separate packages keep the declaration-order/getter matrix independent
        // while compiling the bundled source stdlib only once per route.
        let configurations = [(false, false), (false, true), (true, false), (true, true)]
        let sources = configurations.enumerated().map { index, configuration in
            let (completionDeclaredFirst, useGetter) = configuration
            let completion = """
            private val NO_CB = object : Continuation<Any?> {
                override val context: CoroutineContext \(useGetter ? "get()" : "") = EmptyCoroutineContext
                override fun resumeWith(result: Result<Any?>) {}
            }
            """
            return """
            package sample\(index)
            import kotlin.coroutines.*
            import kotlinx.coroutines.intrinsics.startCoroutineCancellable

            \(completionDeclaredFirst ? completion : calls)
            \(completionDeclaredFirst ? calls : completion)
            """
        }
        try withTemporaryFiles(contents: sources) { paths in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let context = makeCompilationContext(inputs: paths, stdlibLibraryPath: library)
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

    @Test(arguments: [false, true])
    func testElvisArgumentSeesReceiverSubstitutedParameterType(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        // `Result.failure`'s type parameter appears only in its return type, so
        // the call needs the expected `Result<Unit>` propagated through the
        // `?.let { ... } ?: RESUME` elvis argument (Ktor's ByteChannel).
        let source = """
        import kotlin.coroutines.*

        class Task(private val continuation: Continuation<Unit>) {
            fun resume(throwable: Throwable?) {
                continuation.resumeWith(throwable?.let { Result.failure(it) } ?: RESUME)
            }

            companion object {
                val RESUME = Result.success(Unit)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let context = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")
        }
    }

    @Test(arguments: [false, true])
    func testForwardObjectCompletionRejectsNarrowerType(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.intrinsics.startCoroutineCancellable

        fun <R> generic(block: suspend () -> R) {
            block.startCoroutineCancellable(NARROW)
            block.startCoroutineCancellable<R>(NARROW)
        }
        fun concrete(block: suspend () -> String) {
            block.startCoroutineCancellable(NARROW)
            block.startCoroutineCancellable<String>(NARROW)
        }
        private val NARROW = object : Continuation<Int> {
            override val context: CoroutineContext get() = EmptyCoroutineContext
            override fun resumeWith(result: Result<Int>) {}
        }
        """
        try withTemporaryFile(contents: source) { path in
            let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
            let context = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 4, "\(errors.map { "\($0.code): \($0.message)" })")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" })
        }
    }
}
