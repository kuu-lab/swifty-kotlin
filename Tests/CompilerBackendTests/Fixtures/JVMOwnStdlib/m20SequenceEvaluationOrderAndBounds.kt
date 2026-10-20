class Key(val n: Int) { override fun hashCode(): Int { println("hash$n"); return n } }
fun second(): Pair<Key, Int> { println("second"); return Key(2) to 2 }
fun element(): Int { println("left"); return 1 }
fun container(): Sequence<Int> { println("right"); return sequenceOf(1, 2) }
fun argument(n: Int): String { println("arg$n"); return "[$n]" }
fun main() {
    println(element() in container()); println(3 !in sequenceOf(1, 2)); println(1 in listOf(1, 2))
    println(1.to(that = 2))
    println(setOf("a", "b", "a")); println(mapOf(pair = "a" to 1)); println(listOf(element = 1)); println(setOf(element = 2)); println(sequenceOf(element = 3).toList())
    val pairs = arrayOf("a" to 1, "b" to 2); println(mapOf(*pairs)); println(mutableMapOf(pairs = pairs))
    println(mapOf(Key(9) to 9).size); println(setOf(Key(8)).size)
    val first = Key(1) to 1; println(mapOf(first, second()).size)
    var read = 0; println(sequenceOf(1, 2, 3).onEach { read++ }.asIterable().zip(arrayOf(9))); println(read)
    println(sequenceOf("NaN".toDouble(), 1.0).minOrNull()); println(sequenceOf("NaN".toFloat(), 1.0f).minOrNull())
    println(sequenceOf("NaN".toDouble(), 1.0).maxOrNull()); println(sequenceOf("NaN".toFloat(), 1.0f).maxOrNull())
    var consumed = 0; var transformed = 0
    val seq = sequenceOf(1, 2, 3).onEach { consumed++ }
    println(seq.joinToString(limit = 1) { transformed++; "v$it" }); println("$consumed/$transformed")
    consumed = 0; transformed = 0
    println(seq.joinToString(limit = 0) { transformed++; "v$it" }); println("$consumed/$transformed")
    println(sequenceOf(1, 2).joinToString(postfix = argument(1), prefix = argument(2), separator = argument(3)))
    var left = 0; var right = 0
    val xs = sequenceOf(1, 2, 3).map { left++; it }.asIterable()
    val ys = sequenceOf(4).map { right++; it }.asIterable()
    println(xs.zip(ys)); println("$left/$right")
    val values = mutableListOf(1, 2); val view = values.asSequence(); values.add(3); println(view.toList())
    val empty = emptySequence<Int>(); println(empty.toList()); println(sequenceOf<Int>().toList())
    println(sequenceOf(3, 1, 2).sortedDescending().toList())
    println(sequenceOf("bbb", "a", "cc").sortedBy { it.length }.toList())
    println(sequenceOf("bbb", "a", "cc").sortedByDescending { it.length }.toList())
    println(sequenceOf(1, 2).flatMap { listOf(it, it) }.toList())
    println(sequenceOf(listOf(1, 2), listOf(3)).flatten().toList())
    println(sequenceOf(sequenceOf(1), sequenceOf(2)).flatten().toList())
    println(sequenceOf(1, 2, 3).filterIndexed { i, n -> i % 2 == 0 }.toList())
    println(sequenceOf(1, 2, 3).mapIndexedNotNull { i, n -> if (i == 1) null else n }.toList())
    println(sequenceOf(3, 1, 2).minOrNull()); println(sequenceOf(3, 1, 2).maxOrNull())
    println(sequenceOf(1, 2, 3).last()); println(empty.lastOrNull()); println(sequenceOf(1).single())
    println(sequenceOf(1, 2).singleOrNull()); println(sequenceOf(1, 2).elementAt(1)); println(empty.elementAtOrNull(0))
    println(sequenceOf("a" to 1, "a" to 2).toMap())
    println(sequenceOf(1, 2, 1).toMutableSet()); println(sequenceOf(1, 2).count())
    try { empty.first() } catch (e: NoSuchElementException) { println("empty") }
    try { sequenceOf(1, 2).single() } catch (e: IllegalArgumentException) { println("many") }
    try { sequenceOf(1).drop(-1) } catch (e: IllegalArgumentException) { println("drop") }
    try { sequenceOf(1).windowed(0) } catch (e: IllegalArgumentException) { println("window") }
    var seed = 0; val generator = generateSequence({ seed++; 1 }) { if (it < 2) it + 1 else null }
    println(seed); println(generator.toList()); println(generator.toList()); println(seed)
}
