// Proposed source/library O0/O2 controls; NOT COMPILED OR EXECUTED.
// Use with kotlinx.coroutines 1.10.2 / candidate after freeze is lifted.
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.*

fun main() {
    val intResult: Int = runBlocking { 3 }
    val longResult: Long = runBlocking(EmptyCoroutineContext) { 4L }
    val doubleResult: Double = runBlocking(CoroutineName("typed")) { 1.25 }
    val nullableResult: String? = runBlocking(CoroutineName("nullable")) { null as String? }
    val unitResult: Unit = runBlocking { Unit }
    check(intResult == 3 && longResult == 4L && doubleResult == 1.25)
    check(nullableResult == null && unitResult == Unit)

    val prefix = "first"
    val suffix = "second"
    val block: suspend CoroutineScope.() -> String = {
        delay(1)
        prefix + ":" + currentCoroutineContext()[CoroutineName]?.name + ":" + suffix
    }
    val namedReordered: String = runBlocking(block = block, context = CoroutineName("named"))
    check(namedReordered == "first:named:second")

    val defaultValue: Int = runBlocking(block = { 7 })
    val namedLiteral: String = runBlocking(block = {
        delay(1)
        currentCoroutineContext()[CoroutineName]?.name ?: "missing"
    }, context = CoroutineName("literal"))
    check(defaultValue == 7 && namedLiteral == "literal")
    println("generic-results-ok|two-captures-named-value|named-literal")
}
