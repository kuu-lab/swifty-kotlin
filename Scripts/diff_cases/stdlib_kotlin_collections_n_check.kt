// CANDIDATE-ONLY: JVM kotlinc cannot call these @PublishedApi internal functions
// from an ordinary consumer module. Compare candidate stdout to this oracle.
// EXPECT-STDOUT: index:-2147483648 -> ArithmeticException:Index overflow has happened.
// EXPECT-STDOUT: count:-2147483648 -> ArithmeticException:Count overflow has happened.
// EXPECT-STDOUT: index:-1 -> ArithmeticException:Index overflow has happened.
// EXPECT-STDOUT: count:-1 -> ArithmeticException:Count overflow has happened.
// EXPECT-STDOUT: index:0 -> value:0
// EXPECT-STDOUT: count:0 -> value:0
// EXPECT-STDOUT: index:1 -> value:1
// EXPECT-STDOUT: count:1 -> value:1
// EXPECT-STDOUT: index:2147483647 -> value:2147483647
// EXPECT-STDOUT: count:2147483647 -> value:2147483647
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

fun main() {
    val values = intArrayOf(Int.MIN_VALUE, -1, 0, 1, Int.MAX_VALUE)
    for (value in values) {
        for (kind in arrayOf("index", "count")) {
            try {
                val result = if (kind == "index") {
                    kotlin.collections.checkIndexOverflow(value)
                } else {
                    kotlin.collections.checkCountOverflow(value)
                }
                println("$kind:$value -> value:$result")
            } catch (e: ArithmeticException) {
                println("$kind:$value -> ArithmeticException:${e.message}")
            }
        }
    }
}
