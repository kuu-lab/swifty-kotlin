// KOTLINC_FLAGS: -Xassertions=always-enable
// KSWIFTC_FLAGS: -Xassertions=always-enable
// KUU-3817: -Xassertions=always-enable bakes kotlin.assert enabled into the
// compiled artifact on both sides — assert fires even though the JVM runs
// without -ea and the native binary runs without KK_ASSERTIONS_ENABLED.
fun main() {
    try {
        assert(false)
        println("no-throw")
    } catch (e: AssertionError) {
        println("threw ${e.message}")
    }
    var hit = false
    try {
        assert(false) { hit = true; "lazy-msg" }
        println("no-throw2")
    } catch (e: AssertionError) {
        println("threw2 ${e.message} hit=$hit")
    }
    var skipped = true
    assert(true) { skipped = false; "unused" }
    println("skipped=$skipped")
    var cond = false
    assert({ cond = true; true }())
    println("cond=$cond")
    println("done")
}
