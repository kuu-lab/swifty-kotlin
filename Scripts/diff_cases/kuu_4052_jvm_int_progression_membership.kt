// DIFF_JVM: KUU-4052 — JVM IntProgression membership (`in`), `isEmpty`, and
// nested `step` dispatch to kotlin.ranges facade/class methods instead of
// failing with "Unsupported JVM membership receiver/member".
fun main() {
    // Membership on a stepped IntProgression.
    println(5 in (1..6 step 2))
    println(3 in (1..6 step 2))
    println(4 in (1..6 step 2))
    println(5 !in (1..6 step 2))
    println(4 !in (1..6 step 2))
    // Empty progressions never contain a member.
    println(5 in (5..1 step 2))
    // Membership on descending progressions materialized by downTo.
    println(5 in (5 downTo 1))
    println(4 in (5 downTo 1))
    println(6 in (5 downTo 1))
    println(5 in (5 downTo 1 step 2))
    println(3 in (5 downTo 1 step 2))
    println(4 in (5 downTo 1 step 2))
    // isEmpty dispatches on the IntProgression class member.
    println((5..1 step 2).isEmpty())
    println((1..6 step 2).isEmpty())
    println((5 downTo 1 step 2).isEmpty())
    // A raw `downTo` receiver materializes an IntProgression even though its
    // marker type looks like IntRange; member calls must dispatch on the
    // progression class (a JVM IntRange receiver would fail verification).
    println((5 downTo 1).isEmpty())
    println((0 downTo 0).isEmpty())
    println((5 downTo 1).first)
    println((5 downTo 1).last)
    println((5 downTo 1).step)
    println((5 downTo 1).contains(3))
    println((5 downTo 1).reversed())
    val descending = 5 downTo 1
    println(descending.isEmpty())
    println(descending.step)
    println(descending.last)
    println(3 in descending)
    for (i in 3 downTo 1) { println(i) }
    // Nested step resolves the IntProgression.step infix operator.
    println((1..10 step 3) step 2)
    println((6 downTo 1 step 2) step 3)
    val p = 1..10 step 3
    println(p step 2)
    println(p.contains(7))
    println(p.contains(8))
    // Long-range endpoints keep the Long-widened modulo check exact.
    println(1 in (-2147483648..2147483647 step 2))
    println(0 in (-2147483648..2147483647 step 2))
    println(2147483646 in (-2147483648..2147483647 step 2))
    // Existing range surfaces are unchanged.
    println(5 in (1..10))
    println(5 in (1 until 10))
    println((1..6 step 2).first)
    println((1..6 step 2).last)
    println((1..6 step 2).step)
}
