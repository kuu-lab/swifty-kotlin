import kotlin.test.*

class Token(val id: Int) {
    override fun equals(other: Any?): Boolean = other is Token && other.id == id
    override fun hashCode(): Int = id
    override fun toString(): String = "token"
}

fun main() {

    val first = Token(1)
    val second = Token(1)
    assertSame(first, first)
    assertNotSame(first, second)
    assertSame<Token?>(null, null)
    println("identity")
    try { assertSame(first, second) } catch (e: AssertionError) { println(e.message) }
    try { assertNotSame(first, first, "custom") } catch (e: AssertionError) { println(e.message) }
    try { assertNotSame<Token?>(null, null) } catch (e: AssertionError) { println(e.message) }
}
