@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
import kotlin.test.*

fun escape(): String {
    assertFails { return "escaped" }
    return "unreachable"
}
fun main() {
    val original = IllegalStateException("original")
    var calls = 0
    val caught = assertFails { calls++; throw original }
    println("identity:${caught === original}:$calls:${caught.message}")
    println("message:${assertFails("prefix") { throw original } === original}")
    try { assertFails { 42 } } catch (e: AssertionError) { println(e.message) }
    try { assertFails("custom") { null } } catch (e: AssertionError) { println(e.message) }
    try { assertFails { Unit } } catch (e: AssertionError) { println(e.message) }
    val typed: IllegalStateException = assertFailsWith<IllegalStateException> { throw original }
    val parent: Throwable = assertFailsWith<Throwable>("prefix") { throw original }
    val klass: IllegalStateException = assertFailsWith(IllegalStateException::class) { throw original }
    val full = assertFailsWith(IllegalStateException::class, "prefix") { throw original }
    println("typed:${typed === original}:${parent === original}:${klass === original}:${full === original}")
    try { assertFailsWith<IllegalArgumentException>("wrong") { throw original } } catch (e: AssertionError) {
        println("wrong:${e.cause === original}:${e.message?.startsWith("wrong. Expected an exception of ")}")
    }
    try { assertFailsWith<IllegalArgumentException> { "ok" } } catch (e: AssertionError) {
        println("success:${e.cause == null}:${e.message?.contains("completed successfully with the result: <ok>")}")
    }
    println(escape())
}
