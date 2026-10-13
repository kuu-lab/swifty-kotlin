import kotlin.test.*

fun nullableValue(): String? = "present"

fun main() {

    assertNull(null)
    val value = nullableValue()
    val result: String = assertNotNull(value)
    println(result)
    println(value.length)
    try { assertNull("value") } catch (e: AssertionError) { println(e.message) }
    try { assertNotNull<String>(null, "custom") } catch (e: AssertionError) { println(e.message) }
    try { assertNull(1, "") } catch (e: AssertionError) { println(e.message) }
}
