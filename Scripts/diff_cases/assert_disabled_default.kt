// KUU-2751: kotlin.assert is disabled by default on both sides (JVM without
// -ea, kswiftc without KK_ASSERTIONS_ENABLED). The condition argument still
// evaluates as a call argument, but the lazy message is skipped and no
// AssertionError is thrown.
fun main() {
    var conditionEvaluated = false
    var messageEvaluated = false
    assert({ conditionEvaluated = true; false }()) {
        messageEvaluated = true
        "boom"
    }
    println(conditionEvaluated)
    println(messageEvaluated)

    var caught = false
    try {
        assert(false)
    } catch (ae: AssertionError) {
        caught = true
    }
    println(caught)
    println("done")
}
