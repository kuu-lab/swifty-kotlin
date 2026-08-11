fun main() {
    repeat(3) { i ->
        println("iter $i")
    }

    var sum = 0
    repeat(5) {
        sum += it
    }
    println("sum=$sum")

    repeat(0) {
        println("never")
    }

    val n = 4
    var product = 1
    repeat(n) { i ->
        product *= (i + 1)
    }
    println("product=$product")

    var outer = 0
    repeat(3) { i ->
        repeat(2) { j ->
            outer += i * 10 + j
        }
    }
    println("nested=$outer")

    val action: (Int) -> Unit = { v -> println("action $v") }
    repeat(2, action)
}
