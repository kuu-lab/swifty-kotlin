fun <T : Any> retrySource(seed: () -> T?, next: (T) -> T?): Sequence<T> =
    generateSequence(seedFunction = seed, nextFunction = next)

fun main() {
    var seeds = 0
    var nexts = 0
    val generated = retrySource(
        { if (++seeds == 1) throw IllegalStateException("seed") else "a" },
        { if (++nexts == 1) throw IllegalArgumentException("next") else if (it == "a") "b" else null }
    ).iterator()
    println(seeds)
    try { generated.hasNext() } catch (e: IllegalStateException) { println("seed") }
    println(generated.hasNext())
    println(generated.hasNext())
    println(seeds)
    println(generated.next())
    try { generated.next() } catch (e: IllegalArgumentException) { println("next") }
    println(generated.hasNext())
    println(generated.next())
    println(generated.hasNext())
    println(nexts)

    var calls = 0
    val noArg = generateSequence<Int> {
        if (++calls == 1) throw IllegalStateException("producer") else if (calls == 2) 7 else null
    }.iterator()
    try { noArg.next() } catch (e: IllegalStateException) { println("producer") }
    println(noArg.next())
    println(noArg.hasNext())
    println(calls)

    var advances = 0
    val seeded = generateSequence(6) {
        if (++advances == 1) throw IllegalArgumentException("advance") else if (it == 6) 7 else null
    }.iterator()
    println(seeded.next())
    try { seeded.hasNext() } catch (e: IllegalArgumentException) { println("advance") }
    println(seeded.next())
    println(seeded.hasNext())
    println(advances)

    val mixed = sequence<Int> {
        yield(1)
        try {
            yieldAll(iterator<Int> { if (false) yield(99); throw IllegalArgumentException("nested") })
        } catch (e: IllegalArgumentException) { yield(2) }
    }.iterator()
    println(mixed.next())
    println(mixed.next())
    println(mixed.hasNext())

    val later = sequence<Int> {
        yield(1)
        try {
            yieldAll(iterator<Int> { yield(9); throw IllegalArgumentException("later") })
        } catch (e: IllegalArgumentException) { yield(2) }
    }.iterator()
    println(later.next())
    println(later.next())
    try { later.hasNext() } catch (e: IllegalArgumentException) { println("consumer") }

    val nullable: Sequence<String?> = sequence<String?> {
        yield(null)
        try {
            yieldAll(iterator<String?> { if (false) yield(null); throw IllegalArgumentException("nullable") })
        } catch (e: IllegalArgumentException) { yield("caught") }
        yieldAll(emptyList<String?>())
    }
    println(nullable.toList())

    for (count in listOf(0, 1, 3, 4)) {
        val builder = sequence<Int> { for (i in 1..count) yield(i) }
        val chunks = builder.chunked(2) { it.size }.iterator()
        val sizes = mutableListOf<Int>()
        while (chunks.hasNext()) sizes.add(chunks.next())
        println(sizes)
    }
    try {
        sequence<Int> { yield(1) }.chunked(2) { throw IllegalArgumentException("partial") }.toList()
    } catch (e: IllegalArgumentException) { println("partial") }
}
