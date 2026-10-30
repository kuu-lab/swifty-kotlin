// Kotlin 2.1 when guards: `cond if g ->` and `else if g ->` forms.
// Covers false-guard fall-through, smart casts inside guards, guard
// side effects / evaluation order, and guards split across newlines.

var guardCalls = ""

fun probe(tag: String, result: Boolean): Boolean {
    guardCalls += tag
    return result
}

fun classify(x: Any): String = when (x) {
    is String if x.length > 3 -> "long string"
    is String -> "short string"
    is Int if x > 0 -> "positive"
    is Int -> "non-positive"
    else -> "other"
}

fun fallthrough(x: Int): String {
    guardCalls = ""
    val r = when (x) {
        1 if probe("a", false) -> "first"
        1 if probe("b", true) -> "second"
        else -> "other"
    }
    return "$r:$guardCalls"
}

fun guardedElse(x: Any): String = when (x) {
    is Int -> "int"
    else if x is String -> "guarded else string"
    else -> "other"
}

fun newlineGuards(x: Any): String = when (x) {
    is Boolean
        if x -> "true"
    else
        if x is String -> "string"
    else -> "other"
}

fun main() {
    println(classify("hello"))
    println(classify("hi"))
    println(classify(5))
    println(classify(-5))
    println(classify(true))
    println(fallthrough(1))
    println(fallthrough(2))
    println(guardedElse(1))
    println(guardedElse("s"))
    println(guardedElse(1.5))
    println(newlineGuards(true))
    println(newlineGuards("s"))
    println(newlineGuards(0))
}
