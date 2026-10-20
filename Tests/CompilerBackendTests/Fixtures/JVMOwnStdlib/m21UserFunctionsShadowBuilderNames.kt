fun sequence(block: () -> Int): Int = block()
fun iterator(block: () -> Int): Int = block()
fun main() { println(sequence { 42 }); println(iterator { 43 }) }
