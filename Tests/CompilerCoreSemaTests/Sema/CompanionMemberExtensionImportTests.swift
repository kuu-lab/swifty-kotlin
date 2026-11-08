#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct CompanionMemberExtensionImportTests {
    private let declaration = """
        package sample.library
        class Token(val x: Int) {
            companion object {
                inline fun Token.wrapCause(w: (Int) -> Int = { it }): Int = w(x)
            }
        }
        """

    @Test func testImportedCompanionMemberExtensionResolvesAndLowers() throws {
        let usage = """
            package sample.usage
            import sample.library.Token
            import sample.library.Token.Companion.wrapCause

            fun use(t: Token): Int = t.wrapCause()
            fun useWithArgument(t: Token): Int = t.wrapCause { it + 1 }
            """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func testUnimportedCompanionMemberExtensionIsNotGloballyVisible() throws {
        let usage = """
            package sample.usage
            import sample.library.Token

            fun use(t: Token): Int = t.wrapCause()
            """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: diagnosticsForPath(paths[1], in: ctx))
        }
    }

    @Test(arguments: [false, true])
    func companionExtensionPropertyRequiresImport(imported: Bool) throws {
        let declaration = """
        package sample.library
        class Token {
            companion object {
                val Int.doubled: Int get() = this * 2
            }
        }
        """
        let usage = """
        package sample.usage
        \(imported ? "import sample.library.Token.Companion.doubled" : "import sample.library.*")
        fun use(): Int = 3.doubled
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == !imported, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func companionArgumentProvidesExtensionPropertyReceiver() throws {
        let source = """
        class Token {
            companion object {
                val Int.doubled: Int get() = this * 2
            }
        }
        fun <T, R> inScope(receiver: T, block: T.() -> R): R = receiver.block()
        fun use(): Int = inScope(Token) { 3.doubled }
        """
        _ = try SemaFixture(surface: "companion argument receiver").make(source: source)
    }

    @Test
    func importedCompanionExtensionPreservesFBoundedClassType() throws {
        let declaration = """
        package sample
        interface Copyable<T> where T : Throwable, T : Copyable<T> {
            fun createCopy(): T?
        }
        internal val CLOSED = Tok(null)
        internal class Tok(private val origin: Throwable?) {
            companion object {
                inline fun Tok.wrapCause(wrap: (Throwable) -> Throwable): Throwable? {
                    return when (origin) {
                        null -> null
                        is Copyable<*> -> origin.createCopy()
                        else -> wrap(origin)
                    }
                }
            }
        }
        """
        let usage = """
        package sample
        import sample.Tok.Companion.wrapCause

        class Bar {
            fun copy(): Throwable? {
                val x: Tok = CLOSED
                return x.wrapCause { it }
            }
        }
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(memberCallExprIDs(
                named: "wrapCause",
                in: ast,
                path: paths[1],
                ctx: ctx,
                interner: ctx.interner
            ).first)
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee != nil)
        }
    }

    @Test
    func importedCloseTokenCompanionExtensionsPreserveOwnerType() throws {
        let closeToken = """
        package io.ktor.utils.io
        import kotlinx.coroutines.CancellationException
        import kotlinx.coroutines.CopyableThrowable
        import kotlinx.coroutines.ExperimentalCoroutinesApi

        internal fun newCloseToken() = CloseToken(null)
        internal val CLOSED = CloseToken(null)
        internal val CLOSED_FROM_FUNCTION = newCloseToken()
        internal fun requireCloseToken(): CloseToken = CLOSED_FROM_FUNCTION
        internal open class ClosedByteChannelException(cause: Throwable? = null) : Throwable(cause)
        internal class ClosedReadChannelException(cause: Throwable? = null) : ClosedByteChannelException(cause)
        internal class ClosedWriteChannelException(cause: Throwable? = null) : ClosedByteChannelException(cause)

        @OptIn(ExperimentalCoroutinesApi::class)
        internal class CloseToken(private val origin: Throwable?) {
            companion object {
                inline fun CloseToken.wrapCause(
                    wrap: (Throwable) -> Throwable = ::ClosedByteChannelException
                ): Throwable? {
                    return when (origin) {
                        null -> null
                        is CopyableThrowable<*> -> origin.createCopy()
                        is CancellationException -> CancellationException(origin.message, origin)
                        else -> wrap(origin)
                    }
                }

                inline fun CloseToken.throwOrNull(wrap: (Throwable) -> Throwable): Unit? =
                    wrapCause(wrap)?.let { throw it }
            }
        }
        """
        let byteChannel = """
        package io.ktor.utils.io
        import io.ktor.utils.io.CloseToken.Companion.throwOrNull
        import io.ktor.utils.io.CloseToken.Companion.wrapCause
        import kotlinx.atomicfu.atomic

        class ByteChannel {
            private val _closedCause = atomic<CloseToken?>(null)

            fun readBufferCause(): Unit? = _closedCause.value?.throwOrNull(::ClosedReadChannelException)

            fun closedCause(): Throwable? = _closedCause.value?.wrapCause()

            fun close() {
                if (!_closedCause.compareAndSet(expect = null, update = CLOSED)) return
            }
        }
        """
        let sinkByteWriteChannel = """
        package io.ktor.utils.io
        import io.ktor.utils.io.CloseToken.Companion.wrapCause
        import kotlinx.atomicfu.atomic

        class SinkByteWriteChannel {
            private val closed = atomic<CloseToken?>(null)

            fun closedCause(): Throwable? = closed.value?.wrapCause()

            fun close() {
                if (!closed.compareAndSet(expect = null, update = CLOSED)) return
            }

            fun cancel(cause: Throwable?) {
                val token = if (cause == null) CLOSED else CloseToken(cause)
                if (!closed.compareAndSet(expect = null, update = token)) return
            }
        }
        """
        try withTemporaryFiles(contents: [byteChannel, closeToken, sinkByteWriteChannel]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    private let companionExtensionDeclaration = """
        package sample.library
        class Box<T> {
            companion object
        }
        fun <T> Box.Companion.make(v: T): Box<T> = Box()
        """

    private func callableReferenceExprID(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext
    ) -> ExprID? {
        allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .callableRef(_, member, _) = expr else { return false }
            return ctx.interner.resolve(member) == name
        }.first
    }

    @Test
    func importedCompanionExtensionCallableReferenceBindsSingleton() throws {
        let usage = """
            package sample.usage
            import sample.library.Box
            import sample.library.Box.Companion.make

            fun use(): Box<Int> {
                val f: (Int) -> Box<Int> = ::make
                return f(1)
            }
            """
        try withTemporaryFiles(contents: [companionExtensionDeclaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(callableReferenceExprID(
                named: "make",
                in: ast,
                path: paths[1],
                ctx: ctx
            ))
            let binding = try #require(sema.bindings.callableReferenceBinding(for: reference))
            let dispatchReceiver = try #require(binding.dispatchReceiverSymbol)
            #expect(sema.symbols.symbol(dispatchReceiver)?.kind == .object)

            let referenceType = try #require(sema.bindings.exprType(for: reference))
            guard case let .functionType(function) = sema.types.kind(of: referenceType) else {
                Issue.record("Expected a function type for the callable reference.")
                return
            }
            #expect(function.receiver == nil)
            #expect(function.params.count == 1)
        }
    }

    @Test
    func importedCompanionExtensionCallableReferenceSupportsAlias() throws {
        let usage = """
            package sample.usage
            import sample.library.Box
            import sample.library.Box.Companion.make as buildBox

            fun use(): Box<Int> {
                val f: (Int) -> Box<Int> = ::buildBox
                return f(1)
            }
            """
        try withTemporaryFiles(contents: [companionExtensionDeclaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(callableReferenceExprID(
                named: "buildBox",
                in: ast,
                path: paths[1],
                ctx: ctx
            ))
            #expect(sema.bindings.callableReferenceBinding(for: reference)?.dispatchReceiverSymbol != nil)
        }
    }

    @Test
    func unimportedCompanionExtensionCallableReferenceIsRejected() throws {
        let usage = """
            package sample.usage
            import sample.library.Box

            fun use(): Box<Int> {
                val f: (Int) -> Box<Int> = ::make
                return f(1)
            }
            """
        try withTemporaryFiles(contents: [companionExtensionDeclaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0022", in: diagnosticsForPath(paths[1], in: ctx))
        }
    }
}
#endif
