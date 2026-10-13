@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
import kotlin.test.*

object ChangedAsserter : Asserter {
    override fun fail(message: String?): Nothing = throw AssertionError("changed: " + message)
    override fun fail(message: String?, cause: Throwable?): Nothing = throw AssertionError("changed: " + message, cause)
}

fun main() {

    var calls = 0
    expect(42) { calls++; 42 }
    println(calls)
    try { expect(42, "custom") { calls++; 43 } } catch (e: AssertionError) { println(e.message) }
    println(calls)
    try { expect(1) { 2 } } catch (e: AssertionError) { println(e.message) }
    val initialized: Int
    expect(13) { initialized = 13; initialized }
    println(initialized)
    val previous = overrideAsserter(null)
    try {
        try { expect(1) { overrideAsserter(ChangedAsserter); 2 } }
        catch (e: AssertionError) { println(e.message) }
        overrideAsserter(null)
        try { expect(1, "adapter") { overrideAsserter(ChangedAsserter); 2 } }
        catch (e: AssertionError) { println(e.message) }
    } finally { overrideAsserter(previous) }
}
