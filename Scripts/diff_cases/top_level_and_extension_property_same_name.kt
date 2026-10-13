val x: Int = 1
val String.x: Int get() = 2

fun main() {
    println(x)
    println("s".x)
}
