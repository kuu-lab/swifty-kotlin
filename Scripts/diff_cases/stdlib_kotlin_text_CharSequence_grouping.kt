fun main() {
    val text: CharSequence = "banana"
    val counts = text.groupingBy { it }.eachCount()
    println(counts)
    val g: Grouping<Char, Int> = text.groupingBy { ch -> if (ch == 'a') 0 else 1 }
    println(g.eachCount())
    println(text.groupingBy { it }.fold(0) { acc, _ -> acc + 1 })
    println("".groupingBy { it }.eachCount())
}
