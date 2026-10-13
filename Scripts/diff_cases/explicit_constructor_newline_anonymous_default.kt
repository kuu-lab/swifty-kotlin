class Target constructor(val callback: () -> Int =
    fun(): Int { return 7 })
fun after() = 1
fun main() { println(Target().callback()) }
