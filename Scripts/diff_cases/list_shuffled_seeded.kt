import kotlin.random.Random

fun main() {
    // KSP-1511 (BUG): List<T>.shuffled(Random(seed)) used to route through the
    // kk_list_shuffled_random runtime bridge, which ignored the Random
    // instance entirely and always used system entropy (seeded Random did
    // not produce deterministic output). Now source-backed in
    // ListSortingHOF.kt, so seeded output must be bit-exact with kotlinc.
    println(listOf(3, 1, 4, 1, 5, 9, 2, 6).shuffled(Random(7)))
    println(listOf("a", "b", "c", "d", "e").shuffled(Random(7)))
    println(emptyList<Int>().shuffled(Random(7)))
    println(listOf(42).shuffled(Random(7)))

    // Same seed reused across two independent calls must reproduce the same
    // permutation (confirms the seed, not incidental process state, drives
    // the result).
    val source = listOf(10, 20, 30, 40, 50)
    println(source.shuffled(Random(7)) == source.shuffled(Random(7)))

    // Different seeds must (with overwhelming probability, and deterministically
    // for this fixed input) produce different permutations.
    println(source.shuffled(Random(7)) == source.shuffled(Random(42)))
}
