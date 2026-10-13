fun main() {
    // KUU-1431: a nested implicit `it` must bind to the innermost lambda's
    // implicit parameter, not the enclosing lambda's same-named one. The
    // array-constructor init and `repeat` action lambdas are inlined into
    // the enclosing instruction stream, which is where the misbinding
    // showed up ([7, 7, 7, 7] for the first case before the fix).
    listOf(1).forEach {
        println(ByteArray(4) { (it * 7).toByte() }.toList())
    }
    listOf("x").forEach {
        repeat(3) { println(it) }
    }
    // Outer `it` is a String here; the inner `it` must still be the Int index.
    listOf("a").forEach {
        println(IntArray(2) { it }.toList())
    }
    // Inner explicit param: bare `it` still reaches the OUTER element.
    listOf(5).forEach {
        println(IntArray(3) { idx -> idx + it }.toList())
    }
    // Same-name explicit params at both levels: inner `x` shadows outer `x`.
    listOf(10).forEach { x ->
        println(IntArray(3) { x -> x + 1 }.toList())
        println(x)
    }
    // Top-level inlined init with no enclosing lambda.
    println(IntArray(3) { it * 2 }.toList())
    // Three levels: forEach -> repeat -> IntArray init.
    listOf(2).forEach {
        repeat(2) {
            println(IntArray(2) { it }.toList())
        }
    }
    listOf(9).forEach {
        println(IntArray(2) { it }.map { v -> v + 1 })
    }
}
