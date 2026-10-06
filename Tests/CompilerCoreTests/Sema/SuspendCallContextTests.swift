@testable import CompilerCore
import Testing

@Suite
struct SuspendCallContextTests {
    private func diagnostics(_ source: String, includeStdlib: Bool = false) throws -> DiagnosticEngine {
        var result: DiagnosticEngine?
        let input = includeStdlib ? source : "fun println(value: Any?) {}\n" + source
        try withTemporaryFile(contents: input) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: includeStdlib)
            try runSema(ctx)
            result = ctx.diagnostics
        }
        return try requireTestValue(result, "Expected Sema diagnostics")
    }

    @Test
    func issueReproducerRejectsBothCallsButAllowsReference() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        suspend fun caller() = sf()
        fun main() {
            val f: suspend () -> Int = ::sf
            println(f())
            println(::sf)
            println(sf())
        }
        """)
        let errors = result.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "\(result.diagnostics)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0307" })
        #expect(errors.allSatisfy { $0.primaryRange != nil })
    }

    @Test
    func memberExtensionAndExplicitInvokeAreRejected() throws {
        let result = try diagnostics("""
        class Worker { suspend fun work() = 1 }
        class Holder(val f: suspend () -> Int)
        suspend fun String.work() = 2
        fun bad(w: Worker, f: suspend () -> Int, h: Holder) {
            w.work()
            "test".work()
            f.invoke()
            h.f()
            val ext: suspend String.() -> Int = { 1 }
            "test".ext()
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 5, "\(result.diagnostics)")
    }

    @Test
    func suspendFunctionsAndSuspendLambdasAreAccepted() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        suspend fun caller(f: suspend () -> Int) {
            sf()
            f()
            f.invoke()
        }
        fun setup() {
            val f: suspend () -> Int = { sf() }
            val ref = ::sf
        }
        """)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func coroutineBuildersProvideSuspensionContexts() throws {
        let result = try diagnostics("""
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*
        suspend fun sf() = 1
        fun setup() {
            runBlocking {
                sf()
                launch { sf() }.join()
                async { sf() }.await()
            }
            val values = flow { emit(sf()) }
        }
        """, includeStdlib: true)
        #expect(!result.hasError, "\(result.diagnostics)")
    }

    @Test
    func ordinaryNestedFunctionsAndEscapingLambdasDoNotInheritSuspension() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        fun consume(block: () -> Int) = block()
        suspend fun outer() {
            fun local() = sf()
            val stored = { sf() }
            consume { sf() }
            suspend fun localSuspend() = sf()
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 3, "\(result.diagnostics)")
    }

    @Test
    func defaultsAndNominalInitializersCannotInheritSuspension() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        suspend fun defaults(x: Int = sf()) {}
        suspend fun outer() {
            val obj = object {
                val x = sf()
                init { sf() }
                val permitted: suspend () -> Int = { sf() }
            }
            class Local {
                val x = sf()
                init { sf() }
                constructor() { sf() }
            }
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 6, "\(result.diagnostics)")
    }

    @Test
    func operatorSyntaxChecksTheResolvedSuspendCallee() throws {
        let result = try diagnostics("""
        class Operand {
            suspend operator fun plus(other: Operand): Operand = this
            suspend operator fun get(index: Int): Int = index
            suspend infix fun combine(other: Operand): Operand = this
        }
        fun bad(a: Operand) { a + a; a[0]; a combine a }
        suspend fun good(a: Operand) { a + a; a[0]; a combine a }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 3, "\(result.diagnostics)")
    }

    @Test
    func indexedWriteBackAndIterationCheckImplicitSuspendCalls() throws {
        let result = try diagnostics("""
        class Box {
            operator fun get(index: Int): Int = index
            suspend operator fun set(index: Int, value: Int) {}
        }
        class Cursor {
            operator fun hasNext(): Boolean = false
            suspend operator fun next(): Int = 1
        }
        class Values { operator fun iterator(): Cursor = Cursor() }
        fun bad(box: Box, values: Values) {
            box[0] += 1
            for (value in values) { println(value) }
        }
        suspend fun good(box: Box, values: Values) {
            box[0] += 1
            for (value in values) { println(value) }
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 2, "\(result.diagnostics)")
    }

    @Test
    func destructuringChecksSuspendComponents() throws {
        let result = try diagnostics("""
        class Pairish { suspend operator fun component1() = 1 }
        class PairCursor {
            operator fun hasNext(): Boolean = false
            operator fun next(): Pairish = Pairish()
        }
        class PairValues { operator fun iterator(): PairCursor = PairCursor() }
        fun bad(value: Pairish, values: PairValues) {
            val (a) = value
            for ((b) in values) {}
        }
        suspend fun good(value: Pairish, values: PairValues) {
            val (a) = value
            for ((b) in values) {}
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 2, "\(result.diagnostics)")
    }

    @Test
    func inlineLambdaInheritsOnlyAnAvailableSuspensionContext() throws {
        let result = try diagnostics("""
        suspend fun sf() = 1
        inline fun direct(block: () -> Int) = block()
        inline fun escaped(noinline block: () -> Int) = block()
        inline fun crossed(crossinline block: () -> Int) = block()
        suspend fun good() { direct { sf() } }
        fun bad() { direct { sf() } }
        suspend fun escaping() {
            escaped { sf() }
            crossed { sf() }
            val stored = { direct { sf() } }
        }
        """)
        #expect(result.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0307" }.count == 4, "\(result.diagnostics)")
    }
}
