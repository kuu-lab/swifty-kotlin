import kotlinx.coroutines.*
import kotlin.coroutines.CoroutineContext

fun main() = runBlocking {
    println(Dispatchers.IO)
    println(Dispatchers.Unconfined)
    println(Dispatchers.Default)
    println(Dispatchers.IO.toString())
    println(Dispatchers.Unconfined.toString())
    println(Dispatchers.Default.toString())
    val erased: Any = Dispatchers.IO
    val nullable: Any? = Dispatchers.Unconfined
    println(erased.toString())
    println(nullable.toString())
    println("${Dispatchers.Default}")
    println(listOf(Dispatchers.IO, Dispatchers.Unconfined, Dispatchers.Default))
    println(Dispatchers.IO === Dispatchers.Default)
    println(Dispatchers.Unconfined === Dispatchers.Default)
    println(Dispatchers.IO === Dispatchers.IO)
    println(1263223809)
    println(1263223810.toString())
    val number: Any = 1263223812
    println(number)
    println(listOf(1263223809, 1263223810, 1263223812))
    println(withContext(Dispatchers.IO) { "io" })
    println(withContext(Dispatchers.Unconfined) { "unconfined" })
    val context: CoroutineContext = Dispatchers.IO
    println(context.fold("") { _, element -> element.toString() })
    println(context.fold(false) { _, element -> element === Dispatchers.IO })
    val baseContext: CoroutineContext = Dispatchers.Default
    val composed = baseContext + Dispatchers.Unconfined
    println(composed.fold("") { _, element -> element.toString() })
    println(composed.fold(false) { _, element -> element === Dispatchers.Unconfined })
    val task = CoroutineScope(Dispatchers.Unconfined).async {
        currentCoroutineContext().fold(false) { found, element ->
            found || element === Dispatchers.Unconfined
        }
    }
    println(task.await())
}
