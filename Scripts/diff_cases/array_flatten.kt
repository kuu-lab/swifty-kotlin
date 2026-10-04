// KUU-541: Array<out Array<out T>>.flatten() bundled-source overload.
// Array elements whose own type is Iterable (e.g. Array<List<T>>) are a
// KSwiftK-only superset — kotlinc rejects them — so they are exercised by
// stdlib_kotlin_collections_Array_flatten.kt instead of this diff case.
fun main() {
    println(arrayOf(arrayOf(1, 2), arrayOf(3)).flatten())
    println(arrayOf(arrayOf(1), arrayOf(2, 3), arrayOf(4, 5, 6)).flatten())
    println(arrayOf(arrayOf("a", "b"), arrayOf("c")).flatten())
    println(arrayOf<Array<Int>>().flatten())
    println(arrayOf(arrayOf<Int>(), arrayOf(1)).flatten())
    println(arrayOf(arrayOf(1, 2), arrayOf<Int>(), arrayOf(3)).flatten())
}
