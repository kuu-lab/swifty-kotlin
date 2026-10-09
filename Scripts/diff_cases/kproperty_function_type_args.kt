// KUU-1195: a stored KProperty0/1/2 reaches kotlin.FunctionN through
// inheritance (the `() -> V` / `(T) -> V` / `(D, E) -> V` supertypes on the
// bundled KPropertyN interfaces), so it is a subtype of the matching
// function type. Sema used to stop at direct FunctionN symbols and rejected
// these calls with KSWIFTK-SEMA-0002.
import kotlin.reflect.KProperty1

class Box(val value: Int) {
    var mutable: Int = 0
}
class BoxG<T>(val v: T)

fun apply(transform: (Box) -> Int, box: Box): Int = transform(box)
fun supply(transform: () -> Int): Int = transform()
fun <R> supplyG(transform: () -> R): R = transform()
fun <T, R> applyG(transform: (T) -> R, x: T): R = transform(x)
fun applyNullable(transform: ((Box) -> Int)?, box: Box): Int = transform?.invoke(box) ?: -1
fun applyExt(transform: Box.() -> Int, box: Box): Int = box.transform()
fun produce(): (Box) -> Int = Box::value

fun main() {
    val box = Box(3)
    box.mutable = 7
    val property = Box::value
    val bound = box::value
    val mutableProp = box::mutable

    // Non-generic HOFs (the issue's reproducer)
    println(apply(property, box))
    println(supply(bound))

    // Generic HOFs — constraint decomposition must bind R / T
    println(supplyG(bound))
    println(applyG(property, box))
    println(supplyG(mutableProp))
    println(applyG(Box::mutable, box))

    // Bound KMutableProperty0 / unbound KMutableProperty1 through KProperty0/1
    println(supply(mutableProp))
    println(apply(Box::mutable, box))

    // Direct reference passed inline (no stored val)
    println(apply(Box::value, box))
    println(supply(box::value))

    // Nullable function-typed parameter
    println(applyNullable(property, box))

    // Assignment, return position, receiver-style parameter, direct invoke
    val f: (Box) -> Int = property
    println(f(box))
    println(produce()(box))
    println(applyExt(property, box))
    println(property(box))

    // Generic receiver class
    val g: KProperty1<BoxG<Int>, Int> = BoxG<Int>::v
    val f2: (BoxG<Int>) -> Int = g
    println(f2(BoxG(9)))
}
