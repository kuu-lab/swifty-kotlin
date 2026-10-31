// KUU-3899: `x!!` on a statically non-null operand whose runtime slot cannot
// encode a null value must not probe the raw slot — the null-sentinel bit
// pattern is a legitimate payload there (`Long.MIN_VALUE`, `ULong` 2^63,
// `-0.0`), never a null reference. Nullable `IC?` slots and the boxed suspend
// ABI still check the nominal box. JVM agrees on every line below: it boxes
// raw primitives for checkNotNull, probes the `IC?` box, and delivers a box
// through the covariant `IC?`→`IC` suspend override. (JVM's checkNotNull on a
// *direct* flat `Int?` payload throws on `IC(null)` — a JVM carrier artifact
// the ticket deliberately does not reproduce, so no direct `v: IC` `!!` here.)
import kotlin.coroutines.*

@JvmInline
value class VL(val s: Long)

@JvmInline
value class IC(val s: Int?)

fun mkVL(): VL = VL(Long.MIN_VALUE)
fun mkICn(): IC? = IC(null)

var c: Continuation<Any>? = null

suspend fun <T> suspendMe(): T = suspendCoroutine {
    @Suppress("UNCHECKED_CAST")
    c = it as Continuation<Any>
}

interface IBar {
    suspend fun bar(): IC?
}

fun Int?.toResultString() =
    if (this == null) "OK" else "!!! $this"

class Test : IBar {
    override suspend fun bar(): IC = suspendMe()

    suspend fun test1(): String {
        val b: IBar = this
        return b.bar()!!.s.toResultString()
    }

    suspend fun test2(): String {
        return bar()!!.s.toResultString()
    }
}

fun builder(f: suspend () -> Unit) {
    f.startCoroutine(object : Continuation<Unit> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Unit>) {
            result.getOrThrow()
        }
    })
}

fun main() {
    // A flat payload colliding with the sentinel bit pattern is a valid value.
    val vl: VL = mkVL()
    println(vl!!.s)
    println(mkVL()!!.s)
    val l: Long = Long.MIN_VALUE
    println(l!!)
    val u: ULong = 9223372036854775808UL
    println(u!!)

    // The `IC?` slot still checks the nominal box.
    println(mkICn()!!.s == null)
    val n: IC? = null
    try {
        n!!
        println("n nothrow")
    } catch (e: NullPointerException) {
        println("n npe")
    }

    // The boxed suspend ABI delivers a nominal box to `!!` (upstream
    // covariantOverrideSuspendFunWithNullableInlineClass_NullableInt_null).
    var result = "FAIL"
    builder { result = Test().test1() }
    c?.resume(IC(null))
    println(result)

    result = "FAIL2"
    builder { result = Test().test2() }
    c?.resume(IC(null))
    println(result)
}
