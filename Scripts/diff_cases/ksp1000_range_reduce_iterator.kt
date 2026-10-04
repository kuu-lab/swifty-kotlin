fun main() {
    println((1..3).reduce { acc, value -> acc * 10 + value })
    println((1..3).reduceIndexed { index, acc, value -> acc * 10 + value + index })
}
