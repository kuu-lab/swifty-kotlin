// Regression for BUG-174: function type parameter labels (e.g.
// `(acc: Char, Char) -> Char`, `(value: Char) -> Boolean`) must not break
// invocation of the function-typed parameter inside the function body.

fun reduceRepro(s: CharSequence, reduceOperation: (acc: Char, Char) -> Char): Char {
    var accumulator = s[0]
    for (i in 1 until s.length) {
        accumulator = reduceOperation(accumulator, s[i])
    }
    return accumulator
}

fun filterRepro(s: CharSequence, predicate: (value: Char) -> Boolean): String {
    val sb = StringBuilder()
    var i = 0
    while (i < s.length) {
        val c = s[i]
        if (predicate(c)) sb.append(c)
        i++
    }
    return sb.toString()
}

fun indexedRepro(s: CharSequence, op: (index: Int, value: Char) -> Char): String {
    val sb = StringBuilder()
    var i = 0
    while (i < s.length) {
        sb.append(op(i, s[i]))
        i++
    }
    return sb.toString()
}

fun main() {
    println(reduceRepro("abcd") { acc, c -> if (acc < c) acc else c })
    println(filterRepro("Kotlin") { it.isUpperCase() })
    println(indexedRepro("abc") { _, c -> c.uppercaseChar() })
}
