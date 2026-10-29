// KUU-3151: an explicit type argument on a generic call must specialize the
// SAM parameter's method signature, so unannotated lambda parameters bind the
// substituted types. Covers the `in`-projected parameter, its invariant
// boundary, and the explicit-annotation / function-type controls.
fun <T> foo(comparator: Comparator<in T>, a: T, b: T): Int =
    comparator.compare(a, b)

fun <T> bar(comparator: Comparator<T>, a: T, b: T): Int =
    comparator.compare(a, b)

fun <T> baz(fn: (T, T) -> Int, a: T, b: T): Int = fn(a, b)

fun projected(x: Int, y: Int) =
    foo<Int>({ a, b -> a - b }, x, y)

fun invariant(x: Int, y: Int) =
    bar<Int>({ a, b -> a - b }, x, y)

fun annotated(x: Int, y: Int) =
    foo<Int>({ a: Int, b: Int -> a - b }, x, y)

fun functionTyped(x: Int, y: Int) =
    baz<Int>({ a, b -> a - b }, x, y)

fun inferredTypeArgument(x: Int, y: Int) =
    foo({ a, b -> a - b }, x, y)

fun box(): String =
    if (projected(42, 117) < 0 &&
        invariant(42, 117) < 0 &&
        annotated(42, 117) < 0 &&
        functionTyped(42, 117) < 0 &&
        inferredTypeArgument(42, 117) < 0
    ) "OK" else "FAIL"

fun main() { println(box()) }
