// DIFF_JVM
fun main() {
    println((1..<4).toList())
    println((3..<3).isEmpty())
    println((4..<3).isEmpty())
    println((Int.MIN_VALUE..<Int.MIN_VALUE + 1).toList())
    println((Int.MAX_VALUE - 1..<Int.MAX_VALUE).toList())
    println((1..<Int.MIN_VALUE).isEmpty())
    println((Int.MAX_VALUE..<Int.MAX_VALUE).isEmpty())
    println((1..3).toList())
    println((1 until 4).toList())
}
