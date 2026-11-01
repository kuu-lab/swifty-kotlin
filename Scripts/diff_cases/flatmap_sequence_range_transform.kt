// KUU-4063: Sequence.flatMap must select the Iterable-transform overload for
// non-Sequence transform results (ranges, lists, sets); previously it bound
// the Sequence-transform overload and panicked at runtime (KSWIFTK-LINK-0003).
fun main() {
    println(sequenceOf(1, 2, 3).flatMap { 1..it }.toList())
    println(sequenceOf(1, 2, 3).flatMap { listOf(it, it * 10) }.toList())
    println(sequenceOf(1, 2).flatMap { setOf(it, it + 1) }.toList())
    println(sequenceOf(1, 2).flatMap { sequenceOf(it, it * 100) }.toList())
}
