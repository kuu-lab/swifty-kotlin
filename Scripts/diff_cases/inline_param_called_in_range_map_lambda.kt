// KUU-4111: an `inline` parameter invoked inside a lambda that is itself
// inlined does not need `crossinline`. The bundled range/collection `map`
// overloads are `inline`, so the lambdas stay in the caller's inlinable
// context and SEMA-0450 must not fire.

inline fun <T, R> List<T>.zipWithNextCircular(transform: (a: T, b: T) -> R): List<R> =
    indices.map { i -> transform(get(i), get((i + 1) % size)) }

inline fun <R> applyOnIntRange(transform: (Int) -> R): List<R> =
    (0..2).map { transform(it) }

inline fun <R> applyOnIntProgression(transform: (Int) -> R): List<R> =
    (0..6 step 2).map { transform(it) }

inline fun <R> applyOnLongRange(transform: (Long) -> R): List<R> =
    (1L..3L).map { transform(it) }

inline fun <R> applyOnCharRange(transform: (Char) -> R): List<R> =
    ('a'..'c').map { transform(it) }

inline fun <T, R> applyOnArray(transform: (T) -> R, a: Array<T>): List<R> =
    a.map { transform(it) }

inline fun <T, R> applyOnSet(transform: (T) -> R, s: Set<T>): List<R> =
    s.map { transform(it) }

inline fun <R> applyOnIntArray(transform: (Int) -> R, a: IntArray): List<R> =
    a.map { transform(it) }

fun main() {
    println(listOf(1, 2, 3).zipWithNextCircular { a, b -> a + b })
    println(applyOnIntRange { it * 10 })
    println(applyOnIntProgression { it + 1 })
    println(applyOnLongRange { it + 100 })
    println(applyOnCharRange { it.uppercaseChar() })
    println(applyOnArray({ it * 2 }, arrayOf(5, 6)))
    println(applyOnSet({ it + 1 }, setOf(7)))
    println(applyOnIntArray({ it * 3 }, intArrayOf(1, 2)))
}
