import java.lang.Class
import kotlinx.collections.immutable.internal.ASSERTIONS_ENABLED
import kotlinx.collections.immutable.internal.assert as immutableAssert

private class Assertions
fun enabled(): Boolean = Assertions::class.java.desiredAssertionStatus()

fun status(type: Class<*>): Boolean = type.desiredAssertionStatus()

class Bag {
    fun add(x: Int): Int = x
    fun adding(x: Int): Int = add(x)
}

fun main() {
    println(enabled())
    val token = Assertions::class
    val javaView: Class<Assertions> = token.java
    check(token.simpleName == "Assertions")
    println(javaView.desiredAssertionStatus())
    println(status(javaView))
    println(Assertions().javaClass.desiredAssertionStatus())
    println(ASSERTIONS_ENABLED)

    var calls = 0
    var failed = false
    var message: String? = null
    try {
        immutableAssert { calls++; false }
    } catch (e: AssertionError) {
        failed = true
        message = e.message
    }
    println(failed)
    println(calls)
    println(message)

    var kotlinFailed = false
    try {
        kotlin.assert(false)
    } catch (e: AssertionError) {
        kotlinFailed = true
    }
    println(kotlinFailed)
    println(Bag().adding(3))
}
