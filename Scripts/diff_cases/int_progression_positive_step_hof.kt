// KUU-576: source-backed IntProgression HOFs must preserve a positive step.
fun main() {
    println((1..10 step 3).map { it })
    println((1..10 step 3).filter { it > 4 })

    val progression = 1..10 step 3
    progression.forEach { print(it) }
    println()
}
