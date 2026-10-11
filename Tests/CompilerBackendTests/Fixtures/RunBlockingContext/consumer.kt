package runblocking1765.consumer
import kotlinx.coroutines.*
import runblocking1765.producer.*
fun main() {
    val n: Int = invokeInContext(CoroutineName("consumer")) { 11 }
    val l: Long = invokeInContext(CoroutineName("consumer")) { 12L }
    val d: Double = invokeInContext(CoroutineName("consumer")) { 2.5 }
    val s: String = invokeInContext(CoroutineName("consumer")) { "value" }
    val nullable: String? = invokeInContext(CoroutineName("consumer")) { null as String? }
    val unit: Unit = invokeInContext(CoroutineName("consumer")) { Unit }
    check(n == 11 && l == 12L && d == 2.5 && s == "value" && nullable == null && unit == Unit)
    check(storedAndJoined("first", "second") == "first:producer:second")
    println("producer-consumer-generic|stored-two-captures|joined")
}
