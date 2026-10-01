// BUG: compound assignment (`x += rhs`) lowered the right-hand side before
// reading the current target value, so when `rhs` itself mutated the same
// variable (e.g. via `x++`/`++x`), the read/modify/write observed the
// already-mutated value instead of the value Kotlin's left-to-right,
// evaluate-once order requires. Covers every storage kind that compound
// assignment can target: a plain local, a top-level property, a class
// instance field, and a local captured (and boxed) by a closure.
var topLevel = 5

class Box {
    var field = 5
    fun bump() {
        field += field++ + ++field
    }
}

fun main() {
    var local = 5
    local += local++ + ++local
    println(local)

    topLevel += topLevel++ + ++topLevel
    println(topLevel)

    val box = Box()
    box.bump()
    println(box.field)

    var captured = 5
    val bumpCaptured = { captured += captured++ + ++captured }
    bumpCaptured()
    println(captured)
}
