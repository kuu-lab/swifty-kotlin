fun main() {
    var counter = 1
    val increment: () -> Int = { counter++ }
    println(increment())
    println(counter)

    val decrement: () -> Int = { counter-- }
    println(decrement())
    println(counter)

    var arrayCounter = 10
    val values = Array<Int>(2) { arrayCounter++ }
    println(values[0])
    println(values[1])
    println(arrayCounter)
}
