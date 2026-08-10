fun main() {
    val words = listOf("a", "bbb", "cc")
    println(words.sumOf { value: String -> value.length })
    println(words.maxByOrNull { value: String -> value.length })
    println(words.minByOrNull { value: String -> value.length })

    val empty = emptyList<String>()
    println(empty.sumOf { value: String -> value.length })
    println(empty.maxByOrNull { value: String -> value.length })
    println(empty.minByOrNull { value: String -> value.length })
}
