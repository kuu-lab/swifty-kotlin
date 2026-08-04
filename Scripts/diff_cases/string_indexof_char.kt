fun main() {
    val text: CharSequence = "Kotlin"
    println(text.indexOf('o', 0, false))
    println(text.indexOf('k', 0, true))
    println("hello".indexOf('l', 0, false))
    println("hello".indexOf('l', 3, false))
    println("hello".indexOf('l', 4, false))
    println("hello".indexOf('x', 0, false))
    println("hello".indexOf('H', 0, true))
    println("".indexOf('a', 0, false))
    println("abc".indexOf('a', -1, false))
    println("abc".indexOf('a', 5, false))
    println("abc".indexOf('a'))
}
