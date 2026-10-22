fun main() {
    println(1 === 1L)
    val a = 1; val b = 1L
    println(a === b)
    println(a !== b)
    val c: Any = 1; val d: Any = 1L
    println(c === d)
    println(a === 1)
}
