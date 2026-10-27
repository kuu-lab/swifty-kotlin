// KUU-3614: a non-local `return` inside the lazyMessage lambda of the
// kotlin.require / kotlin.check / kotlin.requireNotNull / kotlin.checkNotNull
// family must be legal: the real stdlib declares all of them `inline`, so the
// lambda is not a boundary for KSWIFTK-SEMA-0042. The single-argument overloads
// are inline as well, which keeps the unlabeled `return` targeting the
// enclosing function.

fun requireCase(value: Boolean): String {
    require(value) { return "require-lazy" }
    return "require-ok"
}

fun checkCase(value: Boolean): String {
    check(value) { return "check-lazy" }
    return "check-ok"
}

fun requireNotNullCase(value: String?): String {
    requireNotNull(value) { return "requireNotNull-lazy" }
    return "requireNotNull-ok"
}

fun checkNotNullCase(value: String?): String {
    checkNotNull(value) { return "checkNotNull-lazy" }
    return "checkNotNull-ok"
}

// A `return` crossing two inline lambda boundaries at once, plus contract
// narrowing of the `value != null` condition afterwards.
fun nested(value: String?): String {
    require(value != null) { return "nested-require" }
    check(value.isNotEmpty()) { return "nested-check" }
    return "nested-ok"
}

// kotlin.assert is inline in the real stdlib (@InlineOnly), so its lazy
// lambda is not a non-local-return boundary either. With assertions off by
// default on both sides the lambda never runs, and the call falls through.
fun assertCase(value: Boolean): String {
    assert(value) { return "assert-lazy" }
    return "assert-ok"
}

// A labeled return bound to the lazyMessage lambda itself stays a local
// return and produces the exception message.
fun labeledReturn(value: String?): String {
    try {
        requireNotNull(value) { return@requireNotNull "labeled-message" }
        return "labeled-ok"
    } catch (e: IllegalArgumentException) {
        return e.message ?: "no-message"
    }
}

fun main() {
    println(requireCase(true))
    println(requireCase(false))
    println(checkCase(true))
    println(checkCase(false))
    println(requireNotNullCase("x"))
    println(requireNotNullCase(null))
    println(checkNotNullCase("y"))
    println(checkNotNullCase(null))
    println(nested("name"))
    println(nested(null))
    println(nested(""))
    println(assertCase(true))
    println(assertCase(false))
    println(labeledReturn(null))
    println(labeledReturn("v"))
}
