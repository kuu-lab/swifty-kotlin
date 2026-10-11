import kotlin.test.*

fun main() {

    try { fail() } catch (e: AssertionError) { println(e.message) }
    try { fail("failure") } catch (e: AssertionError) { println(e.message) }
    val cause = IllegalStateException("cause")
    try { fail("failure", cause) } catch (e: AssertionError) {
        println(e.message)
        println(e.cause === cause)
    }
    try { fail(cause = cause) } catch (e: AssertionError) {
        println(e.message)
        println(e.cause === cause)
    }
    val value: String? = "present"
    val found: String = value ?: fail("missing")
    println(found)
    try { val missing: String? = null; println(missing ?: fail("missing")) }
    catch (e: AssertionError) { println(e.message) }
}
