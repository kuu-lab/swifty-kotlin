import kotlin.random.Random

fun main() {
    val values: List<Int> = listOf(1, 2, 2, 3, 5, 8)
    val empty: List<Int> = emptyList()

    // Same seed produces the same element (List-specific overload, KSP-1509).
    val random1 = Random(7)
    val random2 = Random(7)
    println(values.random(random1) == values.random(random2))

    // Deterministic sequence pinned against real kotlinc.
    val seeded = Random(7)
    println(values.random(seeded))
    println(values.random(seeded))
    println(values.random(seeded))

    println(values.random() in values)
    println(values.randomOrNull(Random(7)) in values)
    println(values.randomOrNull() in values)

    // Single-element list always returns that element.
    val single = listOf(42)
    println(single.random())
    println(single.randomOrNull(Random(3)))

    // Empty list: randomOrNull returns null, random throws.
    println(empty.randomOrNull() == null)
    println(empty.randomOrNull(Random(1)) == null)
    try {
        empty.random()
        println(false)
    } catch (e: NoSuchElementException) {
        println(true)
        println(e.message)
    }
    try {
        empty.random(Random(1))
        println(false)
    } catch (e: NoSuchElementException) {
        println(true)
        println(e.message)
    }
}
