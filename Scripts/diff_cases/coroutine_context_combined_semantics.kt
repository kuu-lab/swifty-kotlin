// KUU-4402: CoroutineContext `+`/`minusKey`/`fold`/`toString` must match
// kotlinx's CombinedContext semantics — the ContinuationInterceptor element
// stays rightmost, `minusKey` unwraps to the surviving element (or
// EmptyCoroutineContext), and fold walks insertion order.
import kotlin.coroutines.*
import kotlinx.coroutines.*

class ElemA : CoroutineContext.Element {
    companion object Key : CoroutineContext.Key<ElemA>
    override val key: CoroutineContext.Key<*> get() = Key
}
class ElemB : CoroutineContext.Element {
    companion object Key : CoroutineContext.Key<ElemB>
    override val key: CoroutineContext.Key<*> get() = Key
}

fun kinds(ctx: CoroutineContext, n: CoroutineName, d: CoroutineDispatcher, j: Job): String =
    ctx.fold("") { acc, e ->
        acc + when {
            e === n -> "N"
            e === d -> "D"
            e === j -> "J"
            else -> "?"
        }
    }

fun main() {
    val d = Dispatchers.Default
    val n = CoroutineName("n")
    val j = Job()

    val two = d + n
    // `ctx + EmptyCoroutineContext` returns the same context object and
    // routes through the native composition path.
    val preserved = two + EmptyCoroutineContext
    println(preserved === two)
    println(preserved.toString())
    println(two.toString())
    println((n + d).toString())
    println(two === (n + d))

    val ctx = d + n + j
    val s = ctx.toString()
    println(s.startsWith("[CoroutineName(n), "))
    println(s.endsWith(", Dispatchers.Default]"))
    println(s.contains("Job"))
    println(kinds(ctx, n, d, j))

    val one = ctx.minusKey(Job)
    println(one.toString())
    println(one === two)

    val onlyName = ctx.minusKey(ContinuationInterceptor).minusKey(Job)
    println(onlyName.toString())
    println(onlyName === n)

    val empty = ctx.minusKey(ContinuationInterceptor).minusKey(CoroutineName).minusKey(Job)
    println(empty.toString())
    println(empty === EmptyCoroutineContext)

    val unwrapped = (d + n).minusKey(CoroutineName)
    println(unwrapped === d)
    println(unwrapped.toString())

    val a = ElemA()
    val b = ElemB()
    println((a + b).fold("") { acc, e -> acc + (if (e === a) "A" else "B") })
    println((b + a).fold("") { acc, e -> acc + (if (e === a) "A" else "B") })
    println((a + b).toString().contains("ElemA"))
    println(CoroutineName("solo").toString())
}
