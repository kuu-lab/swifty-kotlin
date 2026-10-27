// KUU-3540: underscore positions in destructuring must be skipped, while a
// backticked `_` is a real variable named `_` that the body can reference.
// Mirrors JetBrains testData codegen/box/multiDecl/forRange/UnderscoreNames.kt.
class Range(val from: C, val to: C) {
    operator fun iterator() = It(from, to)
}

class It(val from: C, val to: C) {
    var c = from.i

    operator fun next(): C {
        val next = C(c)
        c++
        return next
    }

    operator fun hasNext(): Boolean = c <= to.i
}

class C(val i: Int) {
    operator fun component1() = i + 1
    operator fun component2() = i + 2
    operator fun component3() = i + 3
    operator fun rangeTo(c: C) = Range(this, c)
}

fun main() {
    var s = ""
    for ((a, _) in C(0)..C(2)) {
        s += "$a;"
    }
    for ((_, b) in C(1)..C(3)) {
        s += "$b;"
    }
    for ((_, `_`) in C(2)..C(4)) {
        s += "$`_`;"
    }
    val (_, _, v) = C(10)
    s += "$v;"
    val (_, `_`) = C(20)
    s += "${`_`};"
    println(s)
}
