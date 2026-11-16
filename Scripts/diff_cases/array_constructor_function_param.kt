// DIFF_JVM
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
}
