// KUU-4027: a SAM-converted `fun interface` value passed to a generic call is
// a value of the interface type, not of the lambda's function type. The
// argument must satisfy the call's type constraints as `Sup`, not `() -> Int`.
fun interface Sup { fun get(): Int }
fun interface Box<T> { fun unbox(): T }

fun <T> takeIt(x: T): T = x

fun main() {
    // Explicit type argument: the SAM value must satisfy `Sup <: Sup`.
    val lst = listOf<Sup>(Sup { 7 })
    println(lst[0].get())

    // Inferred type argument: the element type is the interface itself.
    val inferred = listOf(Sup { 8 })
    println(inferred[0].get())

    // Generic fun interface, explicit and inferred call type arguments.
    val boxes = listOf<Box<Int>>(Box { 11 })
    println(boxes[0].unbox())
    val inferredBoxes = listOf(Box { 12 })
    println(inferredBoxes[0].unbox())

    // User generic function, explicit type argument and expected-type driven.
    val direct = takeIt<Sup>(Sup { 3 })
    println(direct.get())
    val contextual: Sup = takeIt(Sup { 4 })
    println(contextual.get())

    // Nested generic argument position.
    val pair = Pair<String, Sup>("x", Sup { 9 })
    println(pair.second.get())
}
