fun main() {
    println((2 until 6).toList())
    println((2..<6).toList())
    println((6 downTo 2 step 2).toList())
    println(('a' until 'f').toList())
    println(('a'..< 'f').toList())
    println((2u..<7u).toList())
    println((7uL downTo 2uL step 2).toList())
}
