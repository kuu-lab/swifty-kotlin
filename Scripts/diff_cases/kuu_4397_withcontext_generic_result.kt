import kotlinx.coroutines.*

fun main() = runBlocking {
    val typed: String = withContext(Dispatchers.Default) { "typed-result" }
    println(typed)
    val explicit: Int = withContext<Int>(Dispatchers.Default) { 42 }
    println(explicit)
    val nullable: String? = withContext(Dispatchers.Default) { null as String? }
    println(nullable)
    println(withContext(Dispatchers.Default) { "inferred" })
}
