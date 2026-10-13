// KUU-1693: kotlin.test infrastructure, including inherited default methods.
import kotlin.test.Asserter
import kotlin.test.AsserterContributor
import kotlin.test.DefaultAsserter
import kotlin.test.asserter

class Token {
    override fun toString(): String = "token"
}

object Contributor : AsserterContributor {
    override fun contribute(): Asserter? = DefaultAsserter
}

fun failure(block: () -> Unit) {
    try {
        block()
        println("missing failure")
    } catch (e: AssertionError) {
        println(e.message)
    }
}

fun main() {
    println(asserter === DefaultAsserter)
    println(Contributor.contribute() === DefaultAsserter)
    val adapter: Asserter = DefaultAsserter
    val token = Token()
    adapter.assertTrue(null as String?, true)
    adapter.assertEquals(null, 7, 7)
    adapter.assertNotEquals(null, 7, 8)
    adapter.assertSame(null, token, token)
    adapter.assertNotSame(null, token, Token())
    adapter.assertNull(null, null)
    adapter.assertNotNull(null, token)
    var calls = 0
    adapter.assertTrue({ calls++; "unused" }, true)
    println(calls)
    failure { adapter.assertTrue({ calls++; "lazy failure" }, false) }
    println(calls)
    failure { DefaultAsserter.assertTrue("false value", false) }
    failure { adapter.assertEquals(null, 1, 2) }
    failure { adapter.assertEquals("numbers", 1, 2) }
    failure { adapter.assertEquals("", null, 2) }
    failure { adapter.assertNotEquals("different", 2, 2) }
    failure { adapter.assertSame(null, token, Token()) }
    failure { adapter.assertNotSame(null, token, token) }
    failure { adapter.assertNull(null, "value") }
    failure { adapter.assertNotNull("present", null) }
    failure { adapter.fail(null) }
    val cause = IllegalArgumentException("root")
    try {
        adapter.fail("with cause", cause)
    } catch (e: AssertionError) {
        println(e.message)
        println(e.cause === cause)
    }
    try {
        DefaultAsserter.fail(null, null)
    } catch (e: AssertionError) {
        println(e.message)
        println(e.cause == null)
    }
}
