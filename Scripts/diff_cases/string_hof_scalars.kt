fun main() {
    val text = "abca"
    val charSequence: CharSequence = text

    println(text.count { it == 'a' })
    println(charSequence.count { it > 'b' })
    println("".any { true })
    println(text.any { it == 'c' })
    println(charSequence.all { it >= 'a' && it <= 'z' })
    println(text.none { it == 'z' })
    println(text.indexOfFirst { it == 'c' })
    println(charSequence.indexOfLast { it == 'a' })
}
