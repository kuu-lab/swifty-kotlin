fun main() {
    val s = "hello world"
    println(s.slice(0..4))          // hello
    println(s.slice(6..10))         // world
    println(s.slice(0 until 5))     // hello
    println(s.slice(listOf(0, 1, 4)))   // heo

    val r = 0..4
    println(s.slice(r))             // hello

    println("abcde".slice(1..3))    // bcd
    println("abcde".slice(listOf(4, 2, 0))) // eca
    println("".slice(listOf<Int>())) // (empty)
}
