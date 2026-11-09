// DIFF_JVM
// `until` produces an IntRange whose decl supertype is IntProgression, so the
// `step` infix member must resolve for infix chains and explicit calls.
fun main() {
    for (i in 1 until 8 step 2) print("$i ")
    println()
    println((1 until 5) step 2)
    val p: IntProgression = 1..5
    println(p.step)
    println((0 until 10 step 3).toList())
    for (i in 3 downTo 0 step 10) print("$i ")
    println()
}
