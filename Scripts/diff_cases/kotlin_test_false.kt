import kotlin.test.*

fun contractValue(): Any = "contract"

fun main() {

    assertFalse(false)
    var calls = 0
    assertFalse { calls++; false }
    println(calls)
    val initialized: Int
    assertFalse { initialized = 12; false }
    println(initialized)
    val value = contractValue()
    assertFalse(value !is String)
    println(value.length)
    try { assertFalse(true) } catch (e: AssertionError) { println(e.message) }
    try { assertFalse(true, "custom") } catch (e: AssertionError) { println(e.message) }
    try { assertFalse("") { calls++; true } } catch (e: AssertionError) { println("empty=" + e.message) }
    println(calls)
}
