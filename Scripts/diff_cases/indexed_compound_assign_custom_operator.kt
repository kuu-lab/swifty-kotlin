// KSWIFTK-BUG: `a[i] += v` / `a[i]++` / `a[i]--` on a receiver with a custom
// `operator fun get`/`set` (or a source-backed member pair, e.g.
// MutableList) must dispatch through those operators for both the read and
// the write-back, not the raw built-in array runtime. Before the fix, the
// write silently landed on the receiver's own raw memory layout instead of
// the container it actually indexes into, so the compound assignment had no
// visible effect through the custom accessor.
class IntBucket(private val values: MutableList<Int>) {
    operator fun get(index: Int): Int = values[index]
    operator fun set(index: Int, value: Int) { values[index] = value }
    fun snapshot(): List<Int> = values.toList()
}

class LongIndexedBox {
    private var data: ByteArray = byteArrayOf(9, 8, 7, 6)
    operator fun get(position: Long): Byte = data[position.toInt()]
    operator fun set(position: Long, value: Byte) { data[position.toInt()] = value }
}

class StringBucket(private val values: MutableList<String>) {
    operator fun get(index: Int): String = values[index]
    operator fun set(index: Int, value: String) { values[index] = value }
}

class DoubleBucket(private val values: MutableList<Double>) {
    operator fun get(index: Int): Double = values[index]
    operator fun set(index: Int, value: Double) { values[index] = value }
}

fun main() {
    // Int-indexed custom operator: += must reach the backing list, not
    // corrupt the wrapper object's own memory.
    val ints = IntBucket(mutableListOf(10, 20, 30))
    ints[0] += 5
    ints[1] -= 3
    ints[2] *= 2
    println(ints.snapshot())

    // ++ / -- desugar to the same compound-assign AST node with a
    // synthesized value of 1; must also dispatch through get/set.
    ints[0]++
    ints[1]--
    println(ints.snapshot())

    // Long-indexed custom operator (combines with the get/set literal
    // adaptation fix): plain assignment must go through set(Long, Byte),
    // not kk_array_set on the LongIndexedBox instance itself. (`+=`/`++`
    // aren't used here: Byte.plus(Int) returns Int, which doesn't match
    // set(Long, Byte), so real kotlinc itself rejects that combination as
    // an unresolved '+=' — this class intentionally keeps plain assignment
    // only, matching what's actually valid Kotlin.)
    val box = LongIndexedBox()
    box[0] = box[1]
    println(box[0])
    println(box[1])

    // String element: compound += must use string concatenation, not a
    // numeric op stub.
    val strings = StringBucket(mutableListOf("a", "b"))
    strings[0] += "!"
    println(strings[0])

    // Double element: compound arithmetic must use the floating-point op
    // stubs, not the integer ones.
    val doubles = DoubleBucket(mutableListOf(1.5, 2.5))
    doubles[0] += 0.5
    doubles[1] *= 2.0
    println(doubles[0])
    println(doubles[1])

    // Genuine MutableList<Int> used directly (no wrapping class): its own
    // get/set are real member symbols too and must dispatch the same way.
    val list = mutableListOf(100, 200, 300)
    list[0] += 1
    list[1]++
    println(list)

    // A real built-in array must keep using the raw array/boxing runtime
    // path (regression check for the fallback branch this change leaves
    // otherwise untouched).
    val ia = intArrayOf(1, 2, 3)
    ia[0] += 10
    ia[1]++
    println(ia.joinToString(","))

    val da = doubleArrayOf(1.0, 2.0)
    da[0] += 0.25
    println(da.joinToString(","))

    val boxedArray: Array<Int> = arrayOf(1, 2, 3)
    boxedArray[0] += 100
    boxedArray[1]++
    println(boxedArray.joinToString(","))
}
