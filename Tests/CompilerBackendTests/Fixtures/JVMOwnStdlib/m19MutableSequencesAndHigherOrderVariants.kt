fun grow(b: StringBuilder, c: Char) { if (c == 'a') b.append('c') }
fun main() {
    var reduction = StringBuilder("ab")
    println(reduction.reduce { a, c -> if (c == 'b') reduction.append('c'); c })
    reduction = StringBuilder("ab"); println(reduction.reduceIndexedOrNull { i, a, c -> if (c == 'b') reduction.append('c'); c })
    var b = StringBuilder("ab"); println(b.map { grow(b, it); it })
    b = StringBuilder("ab"); println(b.filter { grow(b, it); true })
    b = StringBuilder("ab"); println(b.filterNot { grow(b, it); false })
    b = StringBuilder("ab"); println(b.filterIndexed { i, c -> grow(b, c); i >= 0 })
    b = StringBuilder("ab"); println(b.fold("") { n, c -> grow(b, c); n + c })
    b = StringBuilder("ab"); println(b.windowed(1) { if (it[0] == 'a') b.append('c'); it.toString() })
    b = StringBuilder("ab"); val same = b.onEach { grow(b, it) }; println(same === b); println(same)
    val cs: CharSequence = StringBuilder("abcd")
    println(cs.filter { it != 'b' }); println(cs.filter { true }.javaClass.name)
    println(cs.takeLastWhile { it != 'b' }); println(cs.dropLastWhile { it != 'b' })
    println(cs.indexOfFirst { it == 'b' }); println(cs.indexOfLast { it == 'b' })
    println(cs.first { it == 'b' }); println(cs.lastOrNull { it == 'z' }); println(cs.findLast { it < 'c' })
    println(cs.single { it == 'c' }); println(cs.singleOrNull { it < 'c' })
    println("abc".mapNotNull { if (it == 'b') null else it.code })
    println("abc".mapIndexedNotNull { i, c -> if (i == 1) null else c.code + i })
    println("ab".flatMap { listOf(it, it) }); println("ab".flatMapIndexed { i, c -> listOf(i + c.code) })
    println("abc".foldIndexed(0) { i, n, c -> n + i + c.code })
    println("abc".foldRightIndexed("") { i, c, n -> n + i + c })
    println("abc".reduce { a, b -> if (a > b) a else b }); println("abc".reduceRight { a, b -> a })
    println("".reduceOrNull { a, b -> a }); println("abc".reduceIndexed { i, a, b -> if (i == 2) b else a })
    println("abc".reduceRightIndexed { i, a, b -> if (i == 0) a else b })
    println("abca".toSet()); println("A😀".map { it.code }); println("ab".toList())
    println("abc".all { it < 'd' }); println("abc".none { it == 'z' }); println("".none()); println("ab".count())
    println("abcde".windowed(size = 3, partialWindows = true, step = 2) { it.length })
    println("abcde".chunked(2) { it.length })
    try { "".reduce { a, b -> a } } catch (e: UnsupportedOperationException) { println("empty") }
    try { "".first { true } } catch (e: NoSuchElementException) { println("missing") }
    try { "ab".single { true } } catch (e: IllegalArgumentException) { println("many") }
}
