// BUG-B: anonymous function expressions `fun(params): RetType { body }`.
// Unlike a lambda literal, `return` inside an anonymous function always
// returns from the anonymous function itself (never a non-local return to
// an enclosing named function), regardless of whether the anonymous
// function ends up inlined into a higher-order call.
fun main() {
    val anon = fun(x: Int): Int {
        if (x < 0) return 0
        return x * 3
    }
    println(anon(2))
    println(anon(-2))

    println(listOf(1, 2, 3).map(fun(x: Int): Int { return x * x }))

    // Anonymous functions capture enclosing locals just like lambdas.
    val offset = 10
    val addOffset = fun(x: Int): Int { return x + offset }
    println(addOffset(5))
    println(listOf(1, 2, 3).map(fun(x: Int): Int { return x + offset }))
}
