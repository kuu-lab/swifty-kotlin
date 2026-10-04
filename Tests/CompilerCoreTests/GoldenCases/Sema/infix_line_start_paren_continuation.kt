package golden.sema

infix fun Int.combine(other: Int): Int = this + other

// KUU-949: a newline before an infix name inside `(` does not end the
// expression — the continuation lines below must all stay in the chain.
fun orChain(a: Int, b: Int, c: Int): Int = (
        a
                or b
                or c
        )

fun combineChain(): Int = (
        1
                combine 2
                combine 3
        )
