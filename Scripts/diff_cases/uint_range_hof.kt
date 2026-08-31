fun main() {
    println((1u..5u).map { it * 2u })
    println((1u..5u).mapIndexed { index, value -> index.toUInt() + value })
    println((1u..5u).mapNotNull { if (it % 2u == 0u) null else it })
    println((1u..5u).filter { it % 2u == 1u })
    println((1u..5u).filterIndexed { index, _ -> index % 2 == 0 })
    println((1u..5u).filterNot { it % 2u == 0u })
    println((5u..1u).mapNotNull { it })
    println((5u..1u).filterIndexed { index, _ -> index == 0 })
    println((5u downTo 1u).mapIndexed { index, value -> index.toUInt() + value })
    println((5u downTo 1u).filterNot { it % 2u == 0u })
}
