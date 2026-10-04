// KSP-410 / BUG-171: a lambda returning into a position the callee declares as a
// type parameter must hand a boxed value to the generic body. Previously a
// `Char`/`Boolean`-returning lambda passed to
// `fun <R> X.f(transform: (Char) -> R): List<R>` leaked the raw scalar, so the
// list printed `[97, 98, 99]` / `[1, 0]` instead of `[a, b, c]` / `[true, false]`.
//
// KSP-410 / BUG-170: a lone bounded type parameter (`R : Any`) inferred purely
// from a nullable-returning lambda body failed with KSWIFTK-TYPE-0001, because
// the body was checked against the unsolvable `R?` instead of its upper bound.
fun <R> String.mapEach(transform: (Char) -> R): List<R> {
    val acc = mutableListOf<R>()
    var i = 0
    while (i < length) {
        acc.add(transform(this[i]))
        i++
    }
    return acc
}

fun <R : Any> String.firstTransformed(transform: (Char) -> R?): R? {
    var i = 0
    while (i < length) {
        val transformed = transform(this[i])
        if (transformed != null) return transformed
        i++
    }
    return null
}

fun main() {
    println("abc".mapEach { it })
    println("abc".mapEach { it.uppercaseChar() })
    println("abc".mapEach { it == 'b' })
    println("abc".mapEach { it.code })
    println("abc".mapEach { "$it!" })

    println("abc".firstTransformed { c -> if (c == 'b') 1 else null })
    println("abc".firstTransformed { c -> if (c == 'b') c.uppercaseChar() else null })
    println("abc".firstTransformed { c -> if (c == 'z') c else null })

    println("abc".map { it })
    println("abc".mapIndexed { i, c -> c })
    println("abc".mapNotNull { c -> if (c == 'b') null else c })
    println("a1b2".firstNotNullOf { c -> if (c.isDigit()) c.digitToInt() else null })
    println("a1b2".firstNotNullOfOrNull { c -> if (c.isUpperCase()) c else null })
}
