import kotlin.coroutines.*

enum class Choice { ONE }
interface CollectionProbe {
    val acceptsNull: Boolean
    fun accepts(value: Any?): Boolean
    fun safe(value: Any?): Boolean
}
inline fun <reified T> direct(value: Any?): Boolean = value is T
inline fun <reified T> captured(): (Any?) -> Boolean = { it is T }
inline fun <reified T> negated(): (Any?) -> Boolean = { it !is T }
inline fun <reified T> safeCast(): (Any?) -> T? = { it as? T }
inline fun <reified T> unsafeCast(): (Any?) -> T = { it as T }
inline fun <reified T> nested(): () -> ((Any?) -> Boolean) = { captured<T>() }
inline fun <reified T> objectProbe(): CollectionProbe = object: CollectionProbe {
    override val acceptsNull: Boolean = null is T
    override fun accepts(value: Any?): Boolean = value is T
    override fun safe(value: Any?): Boolean = (value as? T) != null
}
inline fun <reified T> convert(value: Any?): T = value as T
inline fun <reified T> reference(): (Any?) -> T = ::convert
inline fun <reified T: Any> className(): () -> String = { T::class.java.name }
inline fun <reified T> allocate(): (Int) -> Array<T?> = { arrayOfNulls<T>(it) }
class CollectionGate {
    var pending: Continuation<Int>? = null
    suspend fun await(): Int = suspendCoroutine { pending = it }
    fun release() { pending!!.resume(1) }
}
inline fun <reified T> delayed(gate: CollectionGate): suspend (Any?) -> Boolean = { value ->
    gate.await()
    value is T
}
fun main() {
    val entries: Any = Choice.entries
    val list: Any = emptyList<Int>()
    val set: Any = emptySet<Int>()
    val map: Any = emptyMap<Int, Int>()
    val iterator: Any = emptyList<Int>().iterator()
    println(direct<MutableList<*>>(entries))
    println(captured<MutableList<*>>()(entries)); println(captured<List<*>>()(entries))
    println(captured<MutableIterable<*>>()(list))
    println(captured<MutableIterator<*>>()(iterator))
    println(captured<MutableCollection<*>>()(list))
    println(captured<MutableList<*>>()(list))
    println(captured<MutableSet<*>>()(set)); println(captured<MutableMap<*, *>>()(map))
    println(captured<Iterable<*>>()(list)); println(captured<Iterator<*>>()(iterator))
    println(captured<Collection<*>>()(list)); println(captured<Set<*>>()(set)); println(captured<Map<*, *>>()(map))
    val mutable: Any = mutableListOf(1)
    val jdkSingleton: Any = listOf(1)
    println(captured<MutableList<*>>()(mutable)); println(captured<MutableList<*>>()(jdkSingleton))
    println(captured<MutableSet<*>>()(mutableSetOf(1))); println(captured<MutableMap<*, *>>()(mutableMapOf(1 to 2)))
    println(captured<MutableIterator<*>>()(mutableListOf(1).iterator()))
    println(captured<MutableList<*>>()(map)); println(captured<Any>()(list)); println(captured<String>()(list))
    println(captured<MutableList<*>?>()(null)); println(captured<MutableList<*>>()(null))
    println(negated<MutableList<*>>()(list)); println(negated<MutableList<*>>()(mutable))
    println(safeCast<MutableList<*>>()(list) == null); println(safeCast<MutableList<*>>()(mutable) === mutable)
    println(safeCast<MutableList<*>?>()(null) == null)
    try { unsafeCast<MutableList<*>>()(list); println("wrong") }
    catch (failure: ClassCastException) { println("cast") }
    try { unsafeCast<MutableList<*>>()(null); println("wrong") }
    catch (failure: NullPointerException) { println("null") }
    println(unsafeCast<MutableList<*>>()(mutable) === mutable)
    println(nested<MutableList<*>>()()(entries))
    val objectCheck = objectProbe<MutableList<*>>()
    println(objectCheck.accepts(entries)); println(objectCheck.safe(entries)); println(objectCheck.accepts(mutable))
    println(objectCheck.acceptsNull); println(objectProbe<MutableList<*>?>().acceptsNull)
    try { reference<MutableList<*>>()(entries); println("wrong") }
    catch (failure: ClassCastException) { println("reference") }
    println(reference<MutableList<*>>()(mutable) === mutable)
    println(reference<MutableList<*>?>()(null) == null)
    val arrays: Any = arrayOf(emptyList<Int>())
    println(captured<Array<MutableList<*>>>()(arrays))
    println(className<MutableList<*>>()())
    println(allocate<MutableList<*>>()(1).javaClass.name)
    println(allocate<Array<MutableList<*>>>()(1).javaClass.name)
    val gate = CollectionGate()
    val work: suspend () -> Boolean = { delayed<MutableList<*>>(gate)(entries) }
    work.startCoroutine(object: Continuation<Boolean> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Boolean>) { println(result.getOrThrow()) }
    })
    println("paused"); gate.release()
}
