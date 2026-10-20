// padStart/padEnd reject negative lengths with IllegalArgumentException.
fun main() {
    try {
        println("abc".padStart(-1))
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        println("abc".padEnd(-2, '*'))
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    println("abc".padStart(0))
    println("abc".padStart(5, '*'))
    println("abc".padEnd(5, '*'))
}
