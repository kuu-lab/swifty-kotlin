fun main() {
    fun sumTo(n: Int, acc: Int = 0): Int = if (n == 0) acc else sumTo(n - 1, acc + n)
    println(sumTo(100))
    println(sumTo(3, 10))
    fun greet(name: String, punct: String = "!") = "hi $name$punct"
    println(greet("a"))
    println(greet("b", "?"))

    val base = 100
    var counter = 0
    fun addBase(x: Int, extra: Int = 1): Int {
        counter++
        return base + x + extra
    }
    println(addBase(5))
    println(addBase(5, 10))
    println(addBase(extra = 2, x = 1))
    println(counter)
}
