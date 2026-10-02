// KSWIFTK-BUG: `a[i, j] += v` / `a[i, j]++` / `++a[i, j]` on a receiver with a
// multi-argument custom `operator fun get(i, j)`/`set(i, j, v)` pair must
// dispatch through those operators for both the read and the write-back,
// mirroring the existing single-index fix in
// indexed_compound_assign_custom_operator.kt. Before the prefix-`++`/`--`
// fix, `++a[i, j]` used as its own statement silently did nothing at all:
// the leading `++`/`--` token was left unparsed for any indexed target, so
// the mutation never happened and no diagnostic was produced.
class Grid(val w: Int, val h: Int) {
    private val cells = IntArray(w * h)
    operator fun get(i: Int, j: Int): Int = cells[j * w + i]
    operator fun set(i: Int, j: Int, v: Int) { cells[j * w + i] = v }
    fun dump() = cells.toList()
}

// Index expressions must be evaluated exactly once each for the combined
// read+write, not once per get()/set() call (which would double-count any
// side effect and could also observe a different index on each half).
var sideEffectCounter = 0
fun nextIndex(): Int {
    val v = sideEffectCounter
    sideEffectCounter++
    return v
}

class MixedIndexGrid {
    private val cells = IntArray(4)
    operator fun get(i: Int, j: Long): Int = cells[j.toInt() * 2 + i]
    operator fun set(i: Int, j: Long, v: Int) { cells[j.toInt() * 2 + i] = v }
    fun dump() = cells.toList()
}

class DoubleGrid {
    private val cells = DoubleArray(4)
    operator fun get(i: Int, j: Int): Double = cells[j * 2 + i]
    operator fun set(i: Int, j: Int, v: Double) { cells[j * 2 + i] = v }
    fun dump() = cells.toList()
}

class StringGrid {
    private val cells = arrayOf("", "", "", "")
    operator fun get(i: Int, j: Int): String = cells[j * 2 + i]
    operator fun set(i: Int, j: Int, v: String) { cells[j * 2 + i] = v }
    fun dump() = cells.toList()
}

class Cube {
    private val cells = IntArray(8)
    operator fun get(i: Int, j: Int, k: Int): Int = cells[k * 4 + j * 2 + i]
    operator fun set(i: Int, j: Int, k: Int, v: Int) { cells[k * 4 + j * 2 + i] = v }
    fun dump() = cells.toList()
}

fun main() {
    // Plain multi-index set/get still works (regression guard).
    val g = Grid(2, 2)
    g[0, 0] = 1
    g[1, 1] = 4
    println(g.dump())

    // Compound assignment and postfix/prefix increment through the custom
    // 2-arg get()/set() pair.
    g[1, 0] += 10
    println(g.dump())
    g[0, 1]++
    println(g.dump())
    g[1, 1] *= 3
    println(g.dump())
    println(g[1, 0])

    // Statement-level prefix `++`/`--` on a multi-index custom operator.
    ++g[0, 0]
    println(g.dump())
    --g[0, 0]
    println(g.dump())

    // Index expressions with observable side effects must be evaluated
    // exactly once each across the whole read-modify-write.
    sideEffectCounter = 0
    val se = Grid(4, 4)
    se[nextIndex(), nextIndex()] += 100
    println("sideEffectCounter=" + sideEffectCounter)
    println(se.dump())

    // Mixed index parameter types (Int, Long).
    val mg = MixedIndexGrid()
    mg[0, 0L] = 1
    mg[1, 1L] += 10
    mg[0, 0L]++
    println(mg.dump())

    // Non-Int element types with two indices.
    val dg = DoubleGrid()
    dg[0, 0] = 1.5
    dg[0, 0] += 0.5
    dg[1, 1] *= 2.0
    println(dg.dump())

    val sg = StringGrid()
    sg[0, 0] = "a"
    sg[0, 0] += "!"
    println(sg.dump())

    // Three-argument custom indexed operator: the fix must generalize
    // beyond exactly two indices.
    val cube = Cube()
    cube[0, 0, 0] = 1
    cube[0, 0, 0] += 9
    cube[1, 1, 1]++
    ++cube[0, 1, 0]
    println(cube.dump())
}
