fun greet(name: String): String {
    return "Hello, $name!"
}

fun add(a: Int, b: Int): Int = a + b

fun main() {
    println(greet("World"))
    println(add(5, 3))
}
