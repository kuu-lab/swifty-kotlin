fun main() {
    val text: CharSequence = "Kotlin"
    println(text.lastIndexOf('o', 5, false))
    println(text.lastIndexOf('k', 5, true))
    println("hello".lastIndexOf('l', 4, false))
    println("hello".lastIndexOf('l', 2, false))
    println("hello".lastIndexOf('l', 1, false))
    println("hello".lastIndexOf('x', 4, false))
    println("hello".lastIndexOf('H', 4, true))
    println("".lastIndexOf('a', 0, false))
    println("abc".lastIndexOf('a', -1, false))
}
