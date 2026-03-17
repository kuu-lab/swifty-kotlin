fun main() {
    repeat(3) { println("Hello $it") }
    repeat(0) { println("never") }
    repeat(1) { println("once") }
    var sum = 0
    repeat(5) { sum += it }
    println(sum)
}
