#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SamLambdaUnitCoercionTests {
    @Test
    func nullableFunctionCompareAndSetInsideDisposableHandle() throws {
        // atomicfu is not bundled; preserve its generic API in a source fixture.
        let atomicfu = """
        package kotlinx.atomicfu
        class AtomicRef<T>(var value: T) {
            fun compareAndSet(expect: T, update: T): Boolean = true
        }
        fun <T> atomic(value: T): AtomicRef<T> = AtomicRef(value)
        """
        let source = """
        import kotlinx.atomicfu.*
        import kotlinx.coroutines.*

        class C {
            private val closeHandler = atomic<((Throwable?) -> Unit)?>(null)
            fun reg(handler: (Throwable?) -> Unit): DisposableHandle {
                if (!closeHandler.compareAndSet(null, handler)) throw Error()
                return DisposableHandle { closeHandler.compareAndSet(handler, null) }
            }
        }
        """
        let ctx = makeContextFromSources([atomicfu, source])
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "AtomicRef inside a Unit SAM should type-check: \(errors)")
    }

    @Test(arguments: [
        "Action { true }",
        "Action { 42 }",
        "Action { result() }",
        "consume { result() }",
    ])
    func unitSamDiscardsBodyValue(expression: String) throws {
        let source = """
        fun interface Action { fun run() }
        fun result(): Boolean = true
        fun consume(action: Action): Action = action
        fun make(): Action = \(expression)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unit SAM should discard the body's value: \(errors)")
    }

    @Test(arguments: [
        "IntAction { true }",
        "IntAction { result() }",
        "consume { true }",
    ])
    func nonUnitSamRejectsWrongBodyType(expression: String) throws {
        let source = """
        fun interface IntAction { fun run(): Int }
        fun result(): Boolean = true
        fun consume(action: IntAction): IntAction = action
        fun make(): IntAction = \(expression)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func unitSamStillChecksCompareAndSetArguments() throws {
        let source = """
        import kotlinx.coroutines.DisposableHandle
        class AtomicRef<T>(var value: T) {
            fun compareAndSet(expect: T, update: T): Boolean = true
        }
        fun reg(handler: (Throwable?) -> Unit): DisposableHandle {
            val ref = AtomicRef<((Throwable?) -> Unit)?>(null)
            return DisposableHandle { ref.compareAndSet(handler, 42) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
