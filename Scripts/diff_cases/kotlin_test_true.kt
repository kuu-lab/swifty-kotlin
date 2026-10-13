import kotlin.test.*

fun contractValue(): Any = "contract"

fun main() {

    assertTrue(true)
    var calls = 0
    assertTrue { calls++; true }
    println(calls)
    val initialized: Int
    assertTrue { initialized = 11; true }
    println(initialized)
    val value = contractValue()
    assertTrue(value is String)
    println(value.length)
    try { assertTrue(false) } catch (e: AssertionError) { println(e.message) }
    try { assertTrue(false, "custom") } catch (e: AssertionError) { println(e.message) }
    try { assertTrue("") { calls++; false } } catch (e: AssertionError) { println("empty=" + e.message) }
    println(calls)
}
