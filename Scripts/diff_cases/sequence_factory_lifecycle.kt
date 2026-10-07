fun <T> factory(values: List<T>): Sequence<T> = Sequence(iterator = { values.iterator() })

fun main() {
    println(factory(listOf<String?>(null, "value")).toList())
    println(factory(emptyList<Int>()).toList())
    println(Sequence({ listOf(7).iterator() }).toList())
    println(Sequence { listOf(8).iterator() }.toList())
    println(sequenceOf<Int>().toList())
    println(sequenceOf<String?>(null).toList())

    var seeds = 0
    val generated = generateSequence<Int>(seedFunction = { ++seeds }, nextFunction = { null })
    val first = generated.iterator()
    println(seeds)
    println(first.hasNext())
    println(first.hasNext())
    println(seeds)
    println(first.next())
    println(first.hasNext())
    println(generated.toList())
    println(seeds)
    println(generateSequence<Int>({ null }, { it + 1 }).toList())
    println(generateSequence(0) { it + 1 }.elementAtOrNull(100000))
    println(generateSequence(0) { it + 1 }.take(100001).count())
    println(generateSequence(0) { if (it < 100002) it + 1 else null }.toList().size)
    println(generateSequence("a") { if (it == "a") "b" else null }.toList())

    val producer: () -> Nothing? = { println("producer"); null }
    val nothing: Sequence<Nothing> = generateSequence(producer)
    println(nothing.iterator().hasNext())
    try { nothing.iterator() } catch (e: IllegalStateException) { println("once") }

    var builds = 0
    val built = sequence<Int> { yield(++builds); yield(++builds) }
    val a = built.iterator()
    val b = built.iterator()
    println(builds)
    println(a.hasNext())
    println(a.hasNext())
    println(builds)
    println(a.next())
    println(b.next())
    println(a.next())
    println(b.next())
    println(built.toList())
    println(built.toList())
    println(sequence<String?> { yield(null); yield("item") }.toList())
    println(sequence<Int> { }.toList())

    try {
        iterator<Int> { throw IllegalStateException("iterator boom") }.hasNext()
    } catch (e: IllegalStateException) { println(e.message) }
    try {
        iterator<Int> { throw IllegalArgumentException("next boom") }.next()
    } catch (e: IllegalArgumentException) { println(e.message) }
    try {
        sequence<Int> { yield(1); throw IllegalStateException("sequence boom") }.toList()
    } catch (e: IllegalStateException) { println(e.message) }
    try {
        generateSequence<Int>({ throw IllegalStateException("seed boom") }, { null }).iterator().hasNext()
    } catch (e: IllegalStateException) { println(e.message) }
    try {
        generateSequence(1) { throw IllegalArgumentException("next function boom") }.toList()
    } catch (e: IllegalArgumentException) { println(e.message) }
    try {
        generateSequence<Int> { throw IllegalStateException("producer boom") }.iterator().next()
    } catch (e: IllegalStateException) { println(e.message) }
}
