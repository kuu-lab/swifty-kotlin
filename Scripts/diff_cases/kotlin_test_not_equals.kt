import kotlin.test.*

fun main() {

    assertNotEquals(1, 2)
    assertNotEquals("a", "b")
    assertNotEquals<String?>(null, "value")
    println("different")
    try { assertNotEquals(1, 1) } catch (e: AssertionError) { println(e.message) }
    try { assertNotEquals("a", "a", "custom") } catch (e: AssertionError) { println(e.message) }
    try { assertNotEquals<String?>(null, null, "") } catch (e: AssertionError) { println(e.message) }
}
