// KUU-3573: SAM conversion inside a generic function whose interface type
// arguments are determined by the call's other arguments and by the enclosing
// function's own type parameters (kotlinc codegen/box/funInterface/
// samConversionToGenericInterfaceInGenericFun.kt).
fun interface FunIFace<T, R> {
    fun call(ic: T): R
}

fun <T, R> bar(value: T, f: FunIFace<T, R>): R {
    return f.call(value)
}

class X(val value: Any)

fun <T> gfn(a: X): T =
    bar(a) {
        it.value as T
    }

// Explicit SAM-constructor form of the same shape.
fun <T> gfnConstructor(a: X): T =
    bar(a, FunIFace { x -> x.value as T })

fun main() {
    println(gfn<String>(X("OK")))
    println(gfnConstructor<String>(X("K2")))
}
