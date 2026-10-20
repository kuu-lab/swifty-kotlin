import kotlin.coroutines.*

inline fun forwarded(init: (Int) -> Int): IntArray = IntArray(2) { init(it) }
inline fun noinlineInitializer(noinline init: (Int) -> Int): IntArray = IntArray(1, init)
inline fun shadowedInitializer(init: (Int) -> Int): IntArray {
    val init: (Int) -> Int = { it + 44 }
    return IntArray(1, init)
}
inline fun <reified T> filled(value: T): Array<T> = Array<T>(2) { value }
inline fun <reified T> factory(value: T): () -> Array<T> = { Array<T>(1) { value } }
inline fun <reified T> nestedFactory(value: T): () -> Array<Array<T>> = { Array<Array<T>>(1) { Array<T>(1) { value } } }
fun size(): Int { println("size"); return 2 }
fun callback(): (Int) -> Int { println("callback"); return { it + 10 } }
fun negativeSize(): Int { println("negative-size"); return -1 }
fun throwingCallback(): (Int) -> Int { println("throwing-callback"); throw IllegalStateException("callback") }
var selectedSize = 1
var selectedCallback: (Int) -> Int = { 1 }
fun resizeAndCallback(): (Int) -> Int { selectedSize = 2; return callback() }
fun replaceCallback(): Int { selectedCallback = { 2 }; return 1 }
fun early(): Int {
    try {
        IntArray(2) { index ->
            try { if (index == 0) return 42; index }
            finally { println("element-finally") }
        }
    } finally { println("outer-finally") }
    return 0
}
fun forwardedEarly(): Int { forwarded { return 43 }; return 0 }
class Gate {
    var pending: Continuation<Int>? = null
    suspend fun await(): Int = suspendCoroutine { pending = it }
    fun release(value: Int) { pending!!.resume(value) }
}
fun main() {
    println(early())
    println(forwardedEarly())
    println(noinlineInitializer { it + 45 }[0])
    println(shadowedInitializer { it + 99 }[0])
    val local = IntArray(3) { if (it == 1) return@IntArray 20; it }
    println(local[0]); println(local[1]); println(local[2])
    val ordinary = IntArray(init = callback(), size = size())
    println(ordinary[0]); println(ordinary[1])
    println(IntArray(0) { println("never"); 1 }.size)
    try { IntArray(size = -1, init = callback()) }
    catch (failure: NegativeArraySizeException) { println("negative") }
    try { IntArray(negativeSize(), callback()) }
    catch (failure: NegativeArraySizeException) { println("negative-positional") }
    try { IntArray(init = callback(), size = negativeSize()) }
    catch (failure: NegativeArraySizeException) { println("negative-init-first") }
    try { Array<Int>(size = negativeSize(), init = callback()) }
    catch (failure: NegativeArraySizeException) { println("negative-array") }
    try { Array<Int>(init = callback(), size = negativeSize()) }
    catch (failure: NegativeArraySizeException) { println("negative-array-init-first") }
    println(IntArray(0, callback()).size)
    try { IntArray(-1, throwingCallback()) }
    catch (failure: NegativeArraySizeException) { println("allocation-first") }
    try { IntArray(init = throwingCallback(), size = -1) }
    catch (failure: IllegalStateException) { println("callback-first") }
    val sizeSnapshot = IntArray(selectedSize, resizeAndCallback())
    println(sizeSnapshot.size); println(selectedSize)
    val callbackSnapshot = IntArray(init = selectedCallback, size = replaceCallback())
    println(callbackSnapshot[0])
    try { IntArray(2) { if (it == 1) throw IllegalStateException("stop"); it } }
    catch (failure: IllegalStateException) { println(failure.message) }
    val text = filled("text")
    println(text.javaClass.name); println(text[1])
    println(filled(7).javaClass.name)
    println(filled(arrayOf("nested")).javaClass.name)
    println(factory("escaped")().javaClass.name)
    println(factory<String?>(null)()[0])
    println(nestedFactory("nested")().javaClass.name)
    val gate = Gate()
    val work: suspend () -> Int = {
        val values = IntArray(2) { index ->
            try { gate.await() + index }
            finally { println("resume-finally") }
        }
        values[0] + values[1]
    }
    work.startCoroutine(object: Continuation<Int> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
    })
    println("paused"); gate.release(20)
    println("between"); gate.release(21)
}
