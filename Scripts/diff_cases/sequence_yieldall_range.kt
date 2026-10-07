fun main() {
    println(sequence { yieldAll(1..3) }.toList())
    println(sequence { yield(0); yieldAll(1..3) }.toList())
    println(sequence { yieldAll((1..3) as Iterable<Int>) }.toList())
    println(sequence { val range: IntRange = 1..3; yieldAll(range) }.toList())
    println(sequence { this.yieldAll(1..3) }.toList())
    println(sequence { yieldAll(1 until 4) }.toList())
    println(sequence { yieldAll(3 downTo 1) }.toList())
    println(sequence { yieldAll((1..5) step 2) }.toList())
    println(sequence { yieldAll(1L..3L) }.toList())
    println(sequence { yieldAll('a'..'c') }.toList())
    println(sequence { yieldAll(setOf(1, 2, 3)) }.toList())
}
