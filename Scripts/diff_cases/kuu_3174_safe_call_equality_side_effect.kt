// KUU-3174: `a?.b == c` / `c == a?.b` must not evaluate the non-null operand
// when the safe-call receiver is null. kotlinc lifts the whole comparison
// into the `?.` continuation (`lhs?.equals(rhs) ?: (rhs === null)`), which
// folds to a constant when `rhs` is statically non-nullable.
class C(val x: Int, val d: D?)
class D(val y: Int)
class G(val v: Int) {
    val x: Int get() {
        result += "G"
        return v
    }
}

var result = ""

fun sideEffecting(): Int {
    result += "S"
    return 1
}

fun testNull() {
    val b: C? = null
    result = ""
    println(b?.x == sideEffecting()); println(result)
    result = ""
    println(b?.x != sideEffecting()); println(result)
    result = ""
    println(sideEffecting() == b?.x); println(result)
    result = ""
    println(sideEffecting() != b?.x); println(result)
}

fun testNonNull() {
    val b: C? = C(1, null)
    result = ""
    println(b?.x == sideEffecting()); println(result)
    result = ""
    println(b?.x != sideEffecting()); println(result)
    result = ""
    println(sideEffecting() == b?.x); println(result)
    result = ""
    println(sideEffecting() != b?.x); println(result)
}

fun testNullableRhs() {
    val b: C? = null
    val e: Int? = 7
    println(b?.x == e)
    println(e == b?.x)
    println(b?.x != e)
    println(e != b?.x)
    val n: Int? = null
    println(b?.x == n)
    println(n == b?.x)
}

fun testIdentity() {
    val b: C? = null
    // `===` is a primitive reference compare outside the `?.` continuation:
    // the other operand is still evaluated.
    result = ""
    println(b?.x === sideEffecting()); println(result)
    result = ""
    println(sideEffecting() === b?.x); println(result)
}

fun testChained() {
    val b: C? = null
    result = ""
    println(b?.d?.y == sideEffecting()); println(result)
    result = ""
    println((b?.x) == sideEffecting()); println(result)
    result = ""
    println(b?.x == b?.d?.y); println(result)
}

fun testOrder() {
    // On the non-null path the non-safe operand still observes the member
    // access on the same side of the comparison it was written on:
    // `e == b?.x` evaluates e before b.x; `b?.x == e` evaluates b.x first.
    val g: G? = G(1)
    result = ""
    println(sideEffecting() == g?.x); println(result)
    result = ""
    println(g?.x == sideEffecting()); println(result)
}

fun main() {
    testNull()
    println("---")
    testNonNull()
    println("---")
    testNullableRhs()
    println("---")
    testIdentity()
    println("---")
    testChained()
    println("---")
    testOrder()
}
