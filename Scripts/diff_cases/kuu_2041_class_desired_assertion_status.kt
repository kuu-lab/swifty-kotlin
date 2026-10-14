// JAVA_FLAGS: -ea
// Match the default Native assertion policy when running the JVM reference.
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
