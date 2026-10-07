// A member property of function type inside an object literal: the declared
// type `(Int) -> Int` is parsed through the expression-parser inline type
// path (allowFunctionType = false), so it must fall back to inference-friendly
// nil rather than be consumed as a parenthesized `Int` leaving `-> Int`
// dangling. Regression for AnonymousObjectLocalTypingTests.testRunSemaClean.
interface Runner {
    fun run(value: Int): Int
}

fun main() {
    val local = object : Runner {
        val callback: (Int) -> Int = { value -> value + 1 }
        override fun run(value: Int): Int = this.callback(value)
    }
    println(local.run(41))
}
