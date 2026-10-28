// EXPECT-REJECT
fun main() {
    for (i, j in listOf(1)) {
        println(i)
    }
}
// Kotlin's recovery also reports an unresolved loop variable in the body.
// EXPECT-ERROR-LINES: reference=3,4 candidate=3
