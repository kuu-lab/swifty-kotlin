import kotlin.test.*

class Token(val id: Int) {
    override fun equals(other: Any?): Boolean = other is Token && other.id == id
    override fun hashCode(): Int = id
    override fun toString(): String = "token"
}

fun main() {

    assertEquals(42, 42)
    assertEquals("text", "text")
    assertEquals<String?>(null, null)
    assertEquals(Token(1), Token(1))
    println("equal")
    try { assertEquals(1, 2) } catch (e: AssertionError) { println(e.message) }
    try { assertEquals("a", "b", "custom") } catch (e: AssertionError) { println(e.message) }
    try { assertEquals<String?>(null, "value", "") } catch (e: AssertionError) { println(e.message) }
}
