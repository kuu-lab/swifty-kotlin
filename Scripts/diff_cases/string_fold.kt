fun main() {
    val s = "Hello"

    println(s.fold(0) { acc, c -> acc + c.code })
    println(s.fold("") { acc, c -> acc + c.uppercaseChar() })
    println("".fold(42) { acc, c -> acc + c.code })

    println(s.foldIndexed(0) { index, acc, c -> acc + index * c.code })
    println(s.foldIndexed("") { index, acc, c -> "$acc$index:$c " })
    println("".foldIndexed(-1) { index, acc, c -> acc + index })

    println(s.foldRight(0) { c, acc -> acc + c.code })
    println(s.foldRight("") { c, acc -> acc + c.uppercaseChar() })
    println("".foldRight(42) { c, acc -> acc + c.code })

    println(s.foldRightIndexed(0) { index, c, acc -> acc + index * c.code })
    println(s.foldRightIndexed("") { index, c, acc -> "$acc$index:$c " })
    println("".foldRightIndexed(-1) { index, c, acc -> acc + index })
}
