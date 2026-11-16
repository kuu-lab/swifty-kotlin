// DIFF_JVM
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
import kotlin.concurrent.atomics.AtomicIntArray

// KUU-4599: passing a function-typed parameter directly as the
// `Array(size, init)` / primitive-array `init` argument must still invoke it
// for every element. Before the fix the native lowering only understood
// lambda literals and KIRCallableValueInfo fast-path values, so a plain
// parameter reference silently produced a zero-initialized array.
fun wrap(n: Int, f: (Int) -> Int) = Array(n, f)
fun wrapIA(n: Int, f: (Int) -> Int) = IntArray(n, f)
fun wrapLA(n: Int, f: (Int) -> Long) = LongArray(n, f)
fun wrapBA(n: Int, f: (Int) -> Boolean) = BooleanArray(n, f)
fun wrapCA(n: Int, f: (Int) -> Char) = CharArray(n, f)
fun wrapDA(n: Int, f: (Int) -> Double) = DoubleArray(n, f)

// Side effects prove the initializer really runs once per element.
var calls = 0
fun counter(i: Int): Int { calls += 1; return i * 10 }

// Parameter contravariance lets an init whose declared parameter is
// broader than Int be passed directly; the index is then delivered as an
// erased `Any` value, so `is` checks inside the init must still see a
// boxed Int (a bare integer would make `it is Number` false).
fun takeAny(x: Any): Int = if (x is Number) (x as Number).toInt() * 10 + 1 else -1
fun wrapAny(n: Int, f: (Any) -> Int) = Array(n, f)
fun wrapAnyRef(n: Int) = Array(n, ::takeAny)
fun Int.extPlus1() = this + 1
fun wrapExt(n: Int) = Array(n, Int::extPlus1)
fun wrapAtomicIA(n: Int, f: (Int) -> Int) = AtomicIntArray(n, f)
fun wrapAtomicAny(n: Int, f: (Any) -> Int) = AtomicIntArray(n, f)

fun main() {
    println(wrap(3) { it + 1 }.toList())        // [1, 2, 3]
    println(wrapIA(3) { it + 1 }.toList())      // [1, 2, 3]
    println(wrapLA(3) { it + 1L }.toList())     // [1, 2, 3]
    println(wrapBA(3) { it % 2 == 0 }.toList()) // [true, false, true]
    println(wrapCA(3) { 'a' + it }.toList())    // [a, b, c]
    println(wrapDA(3) { it + 0.5 }.toList())    // [0.5, 1.5, 2.5]

    println(wrapIA(3, ::counter).toList())      // [0, 10, 20]
    println(calls)                              // 3

    // The same call shape in a non-inline helper keeps working.
    val g = { it: Int -> it * 3 }
    println(IntArray(2, g).toList())            // [0, 3]

    println(wrapAny(3, ::takeAny).toList())     // [1, 11, 21]
    println(wrapAnyRef(3).toList())             // [1, 11, 21]
    println(wrapExt(3).toList())                // [1, 2, 3]

    val aa = wrapAtomicIA(3) { it + 1 }
    println(aa.loadAt(0)); println(aa.loadAt(1)); println(aa.loadAt(2))
    val ab = wrapAtomicAny(3, ::takeAny)
    println(ab.loadAt(0)); println(ab.loadAt(1)); println(ab.loadAt(2))
}
