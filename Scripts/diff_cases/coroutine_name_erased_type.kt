import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.Dispatchers

fun lookupName(context: CoroutineContext): CoroutineName? = context[CoroutineName]

fun main() {
    val first = CoroutineName("first")
    val erased: Any = first
    println(erased is CoroutineName)
    println(erased is CoroutineContext.Element)
    println(erased is CoroutineContext)
    println(erased is String)
    println(lookupName(first)?.name)
    println(first[CoroutineName]?.name)
    println(lookupName(EmptyCoroutineContext)?.name)
    val combined: CoroutineContext = Dispatchers.Default + first
    println(lookupName(combined)?.name)
    println(lookupName(combined) === first)
}
