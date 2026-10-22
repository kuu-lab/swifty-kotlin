// JAVA_FLAGS: -ea
// Exercise the assertions-enabled policy on both sides; the harness maps -ea
// to KK_ASSERTIONS_ENABLED=1 on the candidate run.
private class Assertions
fun enabled(): Boolean = Assertions::class.java.desiredAssertionStatus()

fun main() {
    val status = enabled()
    println(status)
    val token = Assertions::class
    val javaView: java.lang.Class<Assertions> = token.java
    println(javaView.desiredAssertionStatus() == status)
    println(Assertions().javaClass.desiredAssertionStatus() == status)
    var failed = false
    try {
        assert(false)
    } catch (e: AssertionError) {
        failed = true
    }
    println(failed == status)
}
