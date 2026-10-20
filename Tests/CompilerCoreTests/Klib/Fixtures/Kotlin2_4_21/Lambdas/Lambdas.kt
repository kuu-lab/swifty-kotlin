package kliblambdas
fun make(): (Int) -> Int = { it + 1 }
fun capture(base: Int): (Int) -> Int = { it + base }
fun twoCaptures(a: Int, b: Int): () -> Int = { a + b }
fun counter(start: Int): () -> Int { var n = start; return { n += 1; n } }
fun invokeInside(value: Int): Int { val f = capture(value); return f(2) }
fun nested(a: Int): (Int) -> () -> Int = { b -> { a + b } }
fun sharedState(): () -> Int { var v = 0; val increment = { v += 1 }; return { increment(); v } }
fun mutateAfterCapture(): Int { var v = 3; val f = { v }; v = 9; return f() }
class Holder(val base: Int) { fun capture(): (Int) -> Int = { base + it } }
fun text(prefix: String): (String) -> String = { prefix + it }
fun <T> keep(value: T): () -> T = { value }
fun binary(base: Int): (Int, Int) -> Int = { a, b -> base + a + b }
fun apply(callback: (Int) -> Int, value: Int): Int = callback(value)
