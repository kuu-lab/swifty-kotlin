class Counter(var value: Int) {
    fun step(): Int {
        value += 1
        return value
    }

    fun runAll() {
        val local: (Int) -> Unit = { println("local ${step()}") }
        local(0)
        listOf(1, 2).forEach { println("each ${step()} $it") }
        repeat(2) { println("repeat ${step()}") }
    }
}

fun main() {
    val counter = Counter(0)
    counter.runAll()
    println("value=${counter.value}")
}
