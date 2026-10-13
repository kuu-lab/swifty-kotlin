// KUU-1978: delegated context bridges must expand stored callbacks at the ABI boundary.
import kotlin.coroutines.*
import kotlinx.coroutines.*

class FoldElement : CoroutineContext.Element {
    companion object Key : CoroutineContext.Key<FoldElement>
    override val key: CoroutineContext.Key<*> get() = Key
}

class FoldContext(val element: FoldElement) : CoroutineContext {
    @Suppress("UNCHECKED_CAST")
    override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? = element as E
    override fun <R> fold(initial: R, operation: (R, CoroutineContext.Element) -> R): R =
        operation(operation(initial, element), element)
    override fun plus(context: CoroutineContext): CoroutineContext = this
    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext = this
}

class FoldDelegate(context: CoroutineContext) : CoroutineContext by context
class FoldJob : Job by Job()

fun foldStep(acc: Int, element: CoroutineContext.Element): Int = acc + 2

fun main() {
    val step = 3
    val seed = 10
    val operation: (Int, CoroutineContext.Element) -> Int = { acc, _ -> acc + step }
    val name = CoroutineName("fold")
    val element = FoldElement()
    val combined = name + element
    println(combined.fold(seed) { acc, _ -> acc + step })
    println(combined.fold(seed, operation))
    val delegatedName: CoroutineContext = FoldDelegate(name)
    println(delegatedName.fold(seed, operation))
    val job: Job = FoldJob()
    println(job.fold(seed, operation))
    val context: CoroutineContext = job
    println(context.fold(seed, operation))
    val delegatedElement: CoroutineContext = FoldDelegate(element)
    println(delegatedElement.fold(seed, operation))
    val delegatedOverride: CoroutineContext = FoldDelegate(FoldContext(element))
    println(delegatedOverride.fold(seed, operation))
    println(name.fold(seed, ::foldStep))
    val prefix = "captured"
    println(delegatedName.fold(prefix) { acc, _ -> acc + ":" + step + ":" + seed })
    try {
        job.fold(seed) { _, _ -> throw IllegalStateException("fold failure") }
    } catch (error: IllegalStateException) {
        println(error.message)
    }
}
