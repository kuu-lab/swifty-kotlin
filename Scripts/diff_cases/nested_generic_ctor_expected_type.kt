// KUU-1370: nested generic constructor calls must receive the expected type
// when a type parameter is not inferable from the call's own arguments.
class D<T : Any, R>(val t: T, val w: Int, val dv: R? = null)
class W1<T : Any>(val d: D<T, T>, val o: Int)
class W2<T : Any, R>(val d: D<T, R>)

// Implicit outer argument position: `D(t, 1)` cannot infer `R` alone; the
// enclosing `W1` parameter `D<T, T>` must supply it.
fun <T : Any> implicitOuter(t: T) = W1(D(t, 1), 0)

// Explicit outer type arguments: `W2<T, Unit>` still determines `R`.
fun <T : Any, R> explicitOuter(t: T): W2<T, Unit> = W2<T, Unit>(D(t, 1))

class OD<T : Any, R>(val t: T, val dv: R? = null)

// if/else branch: the sibling branch's `OD<Boolean, Boolean>` contextualizes
// the else branch's `OD(false)`.
fun branch(b: Boolean): OD<Boolean, Boolean> {
    val d = if (b) OD<Boolean, Boolean>(false) else OD(false)
    return d
}

// Boundary cases that already inferred correctly.
fun <T : Any> directReturn(t: T): D<T, Unit> = D(t, 1)
fun <T : Any> inferredOuter(t: T): W2<T, Unit> = W2(D(t, 1))

fun main() {
    val w1 = implicitOuter(42)
    println(w1.d.t)
    println(w1.d.w)
    println(w1.d.dv)
    println(w1.o)
    val w2 = explicitOuter<Int, Unit>(7)
    println(w2.d.t)
    println(w2.d.dv)
    println(branch(true).t)
    println(branch(false).t)
    println(directReturn("x").w)
    println(inferredOuter("y").d.t)
}
