// BUG-A: parenthesized / nullable function types must parse. Kotlin's type
// grammar allows `(Type)` grouping around any type, most commonly to let a
// trailing `?` bind to a whole function type: `((Int) -> Int)?` is a
// nullable function type, distinct from `(Int) -> Int?` (non-nullable
// function returning `Int?`). The extra parens are also legal without `?`.
fun apply(g: ((Int) -> Int)?, x: Int) = g?.let { it(x) } ?: -1

fun main() {
    val nf: ((Int) -> Int)? = { it + 1 }
    println(nf!!(5))

    val e: ((Int) -> Int) = { it + 1 }
    println(e(1))

    println(apply({ it * 3 }, 2))
    println(apply(null, 2))

    // Non-nullable function returning a nullable Int: the `?` binds to the
    // return type, not the whole function type.
    val f: (Int) -> Int? = { if (it < 0) null else it }
    println(f(5))
    println(f(-5))
}
