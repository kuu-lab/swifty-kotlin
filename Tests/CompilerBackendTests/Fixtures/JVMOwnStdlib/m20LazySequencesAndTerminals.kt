fun main() {
    var calls = 0
    val s = generateSequence(1) { if (it < 5) it + 1 else null }.map { calls++; it * 2 }.filter { it > 2 }.onEach { println("seen$it") }
    println(calls); println(s.drop(1).take(2).joinToString()); println(calls)
    println(s.take(0).toList()); println(calls)
    println(sequenceOf(3, 1, 3, 2).distinct().sorted().toList())
    println(sequenceOf("a", "bb", "c").groupBy { it.length })
    println(sequenceOf(1, 2, 3).associate { it to "v$it" })
    println(sequenceOf(1, 2, 3).partition { it > 1 })
    println(sequenceOf(1, 2, 3).zipWithNext { a, b -> a + b }.toList())
    println(sequenceOf(1, 2).flatMap { sequenceOf(it, it) }.toList())
    println(sequenceOf(1, 2, 3).mapIndexed { i, n -> i + n }.toList())
    println(sequenceOf(1, 2, 3).mapNotNull { if (it == 2) null else it }.toList())
    println(sequenceOf<Int?>(null, 1, null).filterNotNull().toList())
    println(sequenceOf(1, 2, 3).takeWhile { it < 3 }.toList())
    println(sequenceOf(1, 2, 3).dropWhile { it < 2 }.toList())
    println(sequenceOf(1, 2, 3).fold(0) { a, b -> a + b })
    println(sequenceOf(1, 2, 3).any { it == 2 }); println(sequenceOf(1, 2).all { it > 0 })
    println(sequenceOf(1, 2, 3).first { it > 1 }); println(emptySequence<Int>().firstOrNull())
    println(sequenceOf(1, 2, 3).chunked(2).toList()); println(sequenceOf(1, 2, 3).windowed(2, partialWindows = true).toList())
    var n = 0; val once = generateSequence { if (n < 2) ++n else null }; println(once.toList())
    try { once.toList() } catch (e: IllegalStateException) { println("once") }
    val iterator = listOf(4, 5).iterator(); val single = iterator.asSequence(); println(single.toList())
    try { single.toList() } catch (e: IllegalStateException) { println("iterator") }
    try { sequenceOf(1).take(-1) } catch (e: IllegalArgumentException) { println("take") }
    println(sequenceOf(1, 2, 1).distinctBy { it % 2 }.toList())
}
