// EXPECT-REJECT
// KUU-4599: Array(size, init) and the primitive-array (size, init) factories
// are compiler-expanded, not inlined, so forwarding a restricted inline
// parameter to their init slot is a non-inlinable use — kotlinc rejects it
// with "illegal usage of inline parameter".
inline fun <reified T> badArr(f: (Int) -> T): Array<T> = Array(3, f)
inline fun badIA(f: (Int) -> Int): IntArray = IntArray(3, f)
inline fun badLA(f: (Int) -> Long): LongArray = LongArray(3, f)
fun main() {}
