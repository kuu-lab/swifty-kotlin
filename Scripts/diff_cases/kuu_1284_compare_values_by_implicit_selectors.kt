fun <T> two(a: T, b: T, f1: (T) -> Comparable<*>?, f2: (T) -> Comparable<*>?): Int {
    return compareValuesBy(a, b, f1, f2)
}

fun multi(vararg fs: (Int) -> Int): Int {
    var result = 0
    for (f in fs) result += f(3)
    return result
}

fun main() {
    println(compareValuesBy(1, 2, { it }, { it }))
    println(compareValuesBy("a", "b", { it.length }, { it }))
    println(compareValuesBy(1, 2, { it }, { it }, { it }))
    println(compareValuesBy(1, 2, { x: Int -> x }, { it }))
    println(compareValuesBy(1, 2, { it }, { x: Int -> x }))
    println(compareValuesBy(1, 2, { it }, { it }, { it }, { it }))
    println(compareValuesBy(1, 2, { it }))
    println(compareValuesBy(1, 2, reverseOrder<Int>()) { it })
    println(two(1, 2, { it }, { it }))
    println(multi({ it }, { it }))
}
