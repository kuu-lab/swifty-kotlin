fun early(): Int { "abc".map { if (it == 'b') return 42; it }; return 0 }
fun main() {
    val b = StringBuilder("ab"); b.append(charArrayOf('界', 'Z')).append(42).append(true)
    println(b); println(b.length); b[0] = 'A'; println(b[0])
    b.deleteRange(2, 99); b.insert(1, "!"); println(b.reverse()); b.clear(); b.appendLine("x"); println(b.length)
    println(buildString { append("hello"); append('界'); append(42) })
    println("abc".map { it.code }); println("abc".mapIndexed { i, c -> i + c.code })
    println("abc".filter { it != 'b' }); println("abc".filterNot { it == 'b' })
    println("abc".fold(0) { n, c -> n + c.code }); println("abc".foldRight("") { c, n -> n + c })
    println("abc".any { it == 'b' }); println("abc".count { it != 'b' })
    println("abc".takeWhile { it != 'c' }); println("abc".dropWhile { it != 'b' })
    println("abcd".windowed(2)); println("abcde".chunked(2)); println("abc".zipWithNext { a, b -> "" + a + b })
    println(early())
}
