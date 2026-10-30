// KOTLINC_FLAGS: -Xassertions=always-disable
// KSWIFTC_FLAGS: -Xassertions=always-disable
// JAVA_FLAGS: -ea
// KUU-3817: -Xassertions=always-disable wins over runtime enablement on both
// sides — neither `java -ea` nor the harness-provided KK_ASSERTIONS_ENABLED=1
// may make assert fire. kotlinc erases the call at compile time, so neither
// the lazy message nor the condition argument is evaluated.
fun main() {
    var hit = false
    assert(false) { hit = true; "boom" }
    println("hit=$hit")
    var cond = false
    assert({ cond = true; false }())
    println("cond=$cond")
    try {
        assert(false)
        println("no-throw")
    } catch (e: AssertionError) {
        println("threw")
    }
    println("done")
}
