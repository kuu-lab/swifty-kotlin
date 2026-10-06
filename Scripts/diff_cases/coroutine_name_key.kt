import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.Dispatchers

fun lookup(ctx: CoroutineContext): CoroutineName? = ctx[CoroutineName]

fun elementKey(element: CoroutineContext.Element): Boolean = element.key === CoroutineName.Key

fun main() {
    val first = CoroutineName(name = "first")
    val second = CoroutineName("second")
    val key: CoroutineContext.Key<CoroutineName> = CoroutineName
    val standalone: CoroutineContext = first
    println(first.name)
    println(first.key === key)
    println(elementKey(first))
    println(lookup(standalone)?.name)
    println(standalone[CoroutineName.Key] === first)
    println(first[CoroutineName] === first)
    println(first.fold("") { acc, element -> acc + (element[CoroutineName]?.name ?: "missing") })
    println(EmptyCoroutineContext[key]?.name)
    val dispatcher: CoroutineContext = Dispatchers.Default
    println(dispatcher[key]?.name)

    val combined: CoroutineContext = Dispatchers.Default + first
    println(combined.get(CoroutineName)?.name)
    println(combined.fold(0) { count, element -> if (element[key] != null) count + 1 else count })
    val replaced = combined + second
    println(lookup(replaced)?.name)
    println(replaced[key] === second)
    println(lookup(replaced.minusKey(CoroutineName)))
    println(lookup(first.minusKey(key)))
    println(lookup(combined)?.name)
}
