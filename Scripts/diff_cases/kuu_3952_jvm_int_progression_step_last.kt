// DIFF_JVM: KUU-3952 — JVM stdlib IntProgression must align `last` to the
// step like upstream getProgressionLastElement (e.g. (1..6 step 2).last == 5).
fun main() {
    // Basic alignment: the closed-range end is pulled back to the final
    // element reachable by step.
    println((1..6 step 2).last)
    println(1..6 step 2)
    println((1..7 step 2).last)
    println(1..10 step 3)
    println(1..9 step 3)
    println((1..5 step 1).last)
    // Negative direction keeps sign through step.
    println(6 downTo 1 step 2)
    println((6 downTo 1 step 2).last)
    println(5 downTo 1 step 2)
    println(10 downTo 0 step 3)
    // Empty progressions keep the original end bound.
    println(5..1 step 2)
    println(0 downTo 1 step 2)
    // Iteration order is unchanged by the alignment.
    for (x in 1..6 step 2) { println(x) }
    for (x in 10 downTo 0 step 3) { println(x) }
    println((1..6 step 2).toList())
    println((10 downTo 0 step 3).toList())
    println((5..1 step 2).toList())
    // Overflow edges: wrapping arithmetic must not misalign `last`.
    println(0..2147483647 step 2)
    println((2147483645..2147483647 step 2).last)
    println((-2147483648..2147483647 step 3).last)
    println((-2147483648..0 step 2).last)
    println((2147483647 downTo -2147483648 step 3).last)
    // equals/hashCode observe the aligned last element.
    println((1..6 step 2) == (1..5 step 2))
    println((1..6 step 2).hashCode() == (1..5 step 2).hashCode())
}
