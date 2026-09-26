package golden.sema

// BUG-A: `(Type)` grouping around a function type, most commonly used to let
// a trailing `?` bind to the whole function type rather than just its return
// type.
fun applyOrDefault(g: ((Int) -> Int)?, x: Int): Int = g?.let { it(x) } ?: -1

// Extra parens without `?` must also parse (same underlying type, just
// redundantly grouped).
fun makeAdder(): ((Int) -> Int) = { it + 1 }

// Contrast: `?` binds to the return type here, not the whole function type.
fun returnsNullableInt(): (Int) -> Int? = { if (it < 0) null else it }
