fun main() {
    val text = "a1b2"
    println(text.find { it >= '0' && it <= '9' })
    println(text.findLast { it >= '0' && it <= '9' })
    println(text.find { it == 'z' })
    println("".find { true })

    val chars = "Kotlin"
    println(chars.find { it == 't' })
    println(chars.findLast { it == 'o' })
}
