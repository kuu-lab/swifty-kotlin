#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {

    @Test
    func suspendLambdaWithValueClassSpilledFieldPassesVerifier() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.*
        import kotlin.coroutines.intrinsics.*

        private val completion = object : Continuation<Any?> {
            override val context: CoroutineContext = EmptyCoroutineContext
            override fun resumeWith(result: Result<Any?>) { result.getOrThrow() }
        }

        @JvmInline
        value class Offset(val packed: Long)

        private suspend fun suspendHere(): String = suspendCoroutineUninterceptedOrReturn { c ->
            c.resume("K")
            COROUTINE_SUSPENDED
        }

        private fun builder(c: suspend () -> Unit) {
            c.startCoroutine(completion)
        }

        private var result = ""

        fun box(): String {
            builder {
                val a = Offset(7L)
                val s = suspendHere()
                result += "O" + s + a.packed
            }
            builder {
                val b = Offset(9L)
                val s = suspendHere()
                result += "-" + s + b.packed
            }
            if (result != "OK7-K9") return "FAIL: $result"
            return "OK"
        }

        fun main() { println(box()) }
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func externalLoopJumpAnonymousFunctionStaysInlineOnlyPassesVerifier() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        inline fun foo(block: () -> Unit) = block()
        inline fun useBoth(a: () -> Unit, b: () -> Unit) { a(); b() }

        fun main() {
            var i = 0
            outer@ while (i < 5) {
                i++
                foo(fun() { if (i == 2) continue@outer })
                useBoth(fun() { if (i == 4) continue@outer }, fun() {})
            }
            println("done i=" + i)
        }
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        var markerCount = 0
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                guard case let .jump(target) = instruction,
                      KIRExternalLoopJump.label(for: target) != nil
                else { continue }
                markerCount += 1
                #expect(
                    function.isInlineOnly,
                    "external-loop jump marker escaped into non-inline \(ctx.interner.resolve(function.name))"
                )
            }
        }
        #expect(markerCount > 0, "expected at least one external-loop jump marker to be exercised")
    }

    @Test
    func headMemberCallsOnSequenceAndLazyListPassesVerifier() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun <T> Sequence<T>.head(): T = this.iterator().next()
        fun <T> List<T>.headOrNull(): T? = this.firstOrNull()

        sealed class Cakes<out T> {
            abstract fun head(): T
            abstract fun tail(): Cakes<T>
        }
        data class Cons<T>(val v: T, val rest: Cakes<T>) : Cakes<T>() {
            override fun head(): T = v
            override fun tail(): Cakes<T> = rest
        }
        object EmptyCakes : Cakes<Nothing>() {
            override fun head(): Nothing = throw NoSuchElementException()
            override fun tail(): Cakes<Nothing> = this
        }

        fun main() {
            println(sequenceOf(1, 2, 3).head())
            println(listOf(4, 5, 6).headOrNull())
            val cakes: Cakes<Int> = Cons(7, Cons(8, EmptyCakes))
            println(cakes.head())
            println(cakes.tail().head())
        }
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else { continue }
                if ctx.interner.resolve(callee) == "head" {
                    #expect(symbol != nil, "bare `head` callee in \(ctx.interner.resolve(function.name))")
                }
            }
        }
    }

    @Test
    func reflectInvokeConstructorWithDefaultsPassesVerifier() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.reflect.*

        class Cake(val layers: Int = 2, val filling: String = "cream") {
            fun describe() = "cake(${'$'}layers,${'$'}filling)"
        }

        fun main() {
            val k: KFunction<Cake> = ::Cake
            println(k.call(3, "jam").describe())
            println(k.callBy(mapOf()).describe())
            println(k.callBy(mapOf(k.parameters[0] to 5)).describe())
        }
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func suspendCoroutineInsideNestedSuspendLambdaPassesVerifier() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.*

        object EmptyContinuation : Continuation<Unit> {
            override val context: CoroutineContext = EmptyCoroutineContext
            override fun resumeWith(result: kotlin.Result<Unit>) { result.getOrThrow() }
        }
        fun builder(c: suspend () -> Unit) { c.startCoroutine(EmptyContinuation) }

        suspend fun <T> List<T>.onEach(c: suspend (T) -> Unit) { for (e in this) c(e) }
        var c: Continuation<Any>? = null

        fun main() {
            var res = ""
            builder {
                listOf("O", "K").onEach { res += suspendCoroutine<String> { cont ->
                    @Suppress("UNCHECKED_CAST")
                    c = cont as Continuation<Any>
                } }
            }
            c?.resume("O")
            c?.resume("K")
            println(res)
        }
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { continue }
                let calleeName = ctx.interner.resolve(callee)
                #expect(
                    calleeName != "<suspendCoroutineUninterceptedOrReturn>"
                        && calleeName != "suspendCoroutineUninterceptedOrReturn",
                    "unlowered suspend intrinsic in \(ctx.interner.resolve(function.name))"
                )
            }
        }
    }
}
#endif
