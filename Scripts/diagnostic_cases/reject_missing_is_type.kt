// EXPECT-REJECT
fun f() {
    val x = 1 is
}
// The candidate reports the operator; Kotlin reports the following brace.
// EXPECT-ERROR-LINES: reference=4 candidate=3
