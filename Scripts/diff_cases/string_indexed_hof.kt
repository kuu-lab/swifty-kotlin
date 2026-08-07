fun main() {
    val s = "abcde"

    println(s.filterIndexed { index, c -> index % 2 == 0 })
    println("".filterIndexed { index, c -> index % 2 == 0 })

    println(s.mapIndexed { index, c -> "$index$c" })
    println("".mapIndexed { index, c -> "$index$c" })
    val doubled = s.mapIndexed { index, c -> index * c.code }
    println(doubled)

    val sb = StringBuilder()
    val result = s.onEachIndexed { index, c -> sb.append(index).append(c) }
    println(result)
    println(sb.toString())
    println(result === s)

    // BUG-171 regression guard: map/mapIndexed must box Char-preserving
    // transform results, not leak raw scalar codes.
    println("abc".map { it })
    println("abc".map { c -> c.uppercaseChar() })
    println("abc".mapIndexed { i, c -> c })
}
