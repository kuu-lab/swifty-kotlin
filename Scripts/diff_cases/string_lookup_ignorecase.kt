fun main() {
    val s = "Hello World Hello"

    println(s.contains("world", true))
    println(s.contains("world", false))
    println(s.indexOf("world", 0, true))
    println(s.indexOf("world", 0, false))
    println(s.indexOf("Hello", 1, false))
    println(s.indexOf("HELLO", 1, true))
    println(s.lastIndexOf("hello", s.length, true))
    println(s.lastIndexOf("Hello", 11, false))
    println(s.lastIndexOf("HELLO", 11, true))
    println("Hello".indexOf("", 99))
    println("Hello".indexOf("", 99, false))
    println("Hello".indexOf("", 99, true))
    println("Hello".lastIndexOf("", 99, false))
    println("Hello".lastIndexOf("", 99, true))
}
