private class Assertions
fun enabled(): Boolean = Assertions::class.java.desiredAssertionStatus()
fun main() {}
