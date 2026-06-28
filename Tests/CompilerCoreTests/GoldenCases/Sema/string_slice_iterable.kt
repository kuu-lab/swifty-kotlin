package golden.sema

// Regression test: listOf<T>() with explicit type arg and no elements
// must type to List<out T>, not Any, so it matches List<out Int> parameters.
fun useListSliceEmptyExplicitType(): List<Int> = listOf(1, 2, 3).slice(listOf<Int>())

fun useListSliceListOf(): List<Int> = listOf(10, 20, 30).slice(listOf(2, 0))

fun useListSliceRange(): List<Int> = listOf(10, 20, 30).slice(1..2)

fun useListOfExplicitTypeArg(): List<Int> = listOf<Int>()
