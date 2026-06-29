package golden.sema

fun useSliceRange(): String = "hello".slice(1..3)

fun useSliceUntil(): String = "hello".slice(0 until 3)

fun useSliceIterable(): String = "hello".slice(listOf(0, 2, 4))

fun useSliceVar(s: String): String = s.slice(1..3)
