// JAVA_FLAGS: -ea
// The JVM reference exposes these compiler intrinsics through assert().
fun main() {
    var argumentEvaluated = false
    val condition = {
        argumentEvaluated = true
        true
    }
    assert(condition())
    println(argumentEvaluated)

    try {
        assert(false)
    } catch (e: AssertionError) {
        println("caught AssertionError")
    }
}
