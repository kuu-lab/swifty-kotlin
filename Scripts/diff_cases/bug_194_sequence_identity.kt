fun main() {
    println(sequenceOf(1, 2, 3).asIterable().toList())
    println(sequenceOf(1, 2, 3).asSequence().map { it + 1 }.toList())
}
