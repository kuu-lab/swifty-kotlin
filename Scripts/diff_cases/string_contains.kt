fun main() {
    val s = "Hello World Hello"
    println(s.contains("World"))
    println(s.contains("world"))
    println(s.contains("world", true))
    println(s.contains("world", false))
    println(s.contains(""))
    println(s.contains("", true))
    println(s.contains("xyz"))
    println("Hello" in s)
    println("xyz" in s)
    val cs: CharSequence = s
    println(cs.contains("World"))
    println(cs.contains("world", true))
}
