package golden.sema

// Anonymous function expressions `fun(params): RetType { body }`. Unlike a
// lambda literal, `return` inside one always returns from the anonymous
// function itself — never a non-local return to an enclosing named
// function — so this desugars to a synthetic named local function (which
// already gets that return-target semantic right) plus a bound callable
// reference to it.
fun anonymousFunctionExpressions(): Int {
    val square = fun(x: Int): Int { return x * x }
    return square(4)
}
