import kotlin.coroutines.*

enum class CollectionChoice { FIRST, SECOND }
var safeReceiverCalls = 0
var safeArgumentCalls = 0
var safeTouches = 0
class SafeCollectionTarget(val value: Int) {
    fun add(amount: Int): Int = value + amount
    fun touch() { safeTouches++ }
    inline fun inlineTouch(action: () -> Unit) { try { action() } finally { safeTouches++ } }
    inline suspend fun inlineSuspendTouch(action: () -> Unit) { try { action() } finally { println("inline-suspend-finally") } }
}
fun safeReceiver(present: Boolean): SafeCollectionTarget? {
    safeReceiverCalls++
    return if (present) SafeCollectionTarget(10) else null
}
fun safeArgument(): Int { safeArgumentCalls++; return 5 }

fun inlineEarly(present: Boolean): String {
    val target: SafeCollectionTarget? = if (present) SafeCollectionTarget(0) else null
    try {
        target?.inlineTouch { return "inline-early" }
        return "inline-null"
    } finally { println("inline-outer-finally") }
}
class SafeInlineGate {
    var pending: Continuation<Unit>? = null
    suspend fun await(): Unit = suspendCoroutine { pending = it }
    fun release() { pending!!.resume(Unit) }
}
class SafeInlineCompletion: Continuation<Unit> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) { result.getOrThrow(); println("inline-complete") }
}

fun checkList(value: Any) {
    println(value is MutableList<*>)
    println(value as? MutableList<*> == null)
    try {
        val list = value as MutableList<Int>
        println("mutable")
    } catch (failure: ClassCastException) {
        println("readonly")
    }
}

fun main() {
    checkList(CollectionChoice.entries)
    checkList(emptyList<Int>())
    checkList(mutableListOf(1))
    val set: Any = emptySet<Int>()
    val map: Any = emptyMap<Int, String>()
    println(set is MutableSet<*>)
    println(set as? MutableSet<*> == null)
    println(map is MutableMap<*, *>)
    println(map as? MutableMap<*, *> == null)
    println(mutableSetOf(1) is MutableSet<*>)
    println(mutableMapOf(1 to "one") is MutableMap<*, *>)
    val values = emptyMap<Int, String>()
    println(values.keys is MutableSet<*>)
    println(values.values is MutableCollection<*>)
    println(emptyList<Int>().iterator() is MutableIterator<*>)
    println(emptySet<Int>().iterator() is MutableIterator<*>)
    println(mutableListOf(1).iterator() is MutableIterator<*>)
    val absent: Any? = null
    println(absent is MutableList<*>?)
    println(absent as? MutableList<*> == null)
    val iterable: Any = mutableListOf(7)
    println(iterable is MutableIterable<*>)
    println((iterable as MutableIterable<Int>).iterator().next())
    println((iterable as? MutableIterable<Int>)?.iterator()?.next())
    println((absent as? MutableIterable<Int>)?.iterator()?.hasNext())
    println(absent as MutableList<Int>? == null)
    println(absent as MutableSet<Int>? == null)
    println(absent as MutableMap<Int, String>? == null)
    println(absent as MutableCollection<Int>? == null)
    println(absent as MutableIterator<Int>? == null)
    println(absent as MutableIterable<Int>? == null)
    try { println((absent as MutableList<Int>).size) } catch (failure: NullPointerException) { println("null list") }
    try { println((absent as MutableSet<Int>).size) } catch (failure: NullPointerException) { println("null set") }
    try { println((absent as MutableMap<Int, String>).size) } catch (failure: NullPointerException) { println("null map") }
    try { println((absent as MutableCollection<Int>).size) } catch (failure: NullPointerException) { println("null collection") }
    try { println((absent as MutableIterator<Int>).hasNext()) } catch (failure: NullPointerException) { println("null iterator") }
    try { println((absent as MutableIterable<Int>).iterator().hasNext()) } catch (failure: NullPointerException) { println("null iterable") }
    println(emptyList<Int>() == emptyList<Int>())
    println(emptySet<Int>().hashCode())
    println(emptyMap<Int, String>().hashCode())
    println(emptySet<Int>().equals(emptySet<Int>()))
    println(emptyMap<Int, String>().toString())
    val groups = Regex("(a)(b)?").find("a")!!.groups
    println(groups.toList())
    println(groups.toMutableList().size)
    println(groups.toSet().size)
    println(groups is MutableCollection<*>)
    println(groups.iterator() is MutableIterator<*>)
    println(safeReceiver(false)?.add(safeArgument()))
    println(safeReceiverCalls); println(safeArgumentCalls)
    println(safeReceiver(true)?.add(safeArgument()))
    println(safeReceiverCalls); println(safeArgumentCalls)
    println(safeReceiver(false)?.value)
    println(safeReceiver(true)?.value)
    println(safeReceiver(false)?.touch())
    println(safeReceiver(true)?.touch())
    println(safeReceiverCalls); println(safeTouches)
    safeReceiver(false)?.touch(); safeReceiver(true)?.touch()
    println(safeReceiverCalls); println(safeTouches)
    val number: Int? = 19
    val noNumber: Int? = null
    println(number?.toInt())
    println(noNumber?.toInt())
    println(number?.plus(2))
    println(noNumber?.plus(2))
    println(1?.plus(2))
    val builder: StringBuilder? = StringBuilder("abc")
    val absentBuilder: StringBuilder? = null
    println(builder?.setLength(0))
    println(builder?.length)
    println(absentBuilder?.setLength(safeArgument()))
    println(safeArgumentCalls)
    val inlinePresent: SafeCollectionTarget? = SafeCollectionTarget(0)
    val inlineAbsent: SafeCollectionTarget? = null
    println(inlinePresent?.inlineTouch { println("inline-called") })
    println(inlineAbsent?.inlineTouch { println("inline-never") })
    println(safeTouches)
    println(inlineEarly(true)); println(inlineEarly(false)); println(safeTouches)
    val gate = SafeInlineGate()
    val work: suspend () -> Unit = {
        println(inlinePresent?.inlineSuspendTouch { gate.await(); println("inline-resumed") })
        println(inlineAbsent?.inlineSuspendTouch { println("inline-never") })
    }
    work.startCoroutine(SafeInlineCompletion())
    println("inline-paused")
    gate.release()
}
