// KUU-541: Array<out Array<out T>>.flatten() (upstream) and
// Array<out Iterable<T>>.flatten() (KSwiftK superset) — receiver overload
// selection and element type propagation.

fun flattenArrays(values: Array<out Array<out Int>>): List<Int> = values.flatten()

fun main() {
    val nested: Array<Array<Int>> = arrayOf(arrayOf(1, 2), arrayOf(3))
    val lists = arrayOf(listOf(4, 5), listOf(6))

    println(nested.flatten())
    println(lists.flatten())
    println(flattenArrays(nested))
}
