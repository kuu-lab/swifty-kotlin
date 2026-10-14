// KUU-2044: generic Array.fill defaults, nullable writes, and range validation.
fun clear(xs: Array<Any?>) { xs.fill(null, 1, 2) }

// The three fill call sites in PersistentVectorBuilder.kt at commit
// 9f961e4dd419dff58ffea164dd41ebba68acc8d6 (lines 772, 834, 865).
fun clearVectorBuffers(newTail: Array<Any?>, newRoot: Array<Any?>,
                       newTailSize: Int, lastIndex: Int, tailSize: Int) {
    val MAX_BUFFER_SIZE = 32
    newTail.fill(null, newTailSize, MAX_BUFFER_SIZE)
    newRoot.fill(null, lastIndex + 1, MAX_BUFFER_SIZE)
    newTail.fill(null, newTailSize, tailSize)
}

fun fillContravariant(xs: Array<in String>) { xs.fill("in", 1, 2) }
fun <T> fillGeneric(xs: Array<T>, element: T) { xs.fill(element, 0, 1) }

fun checkRange(fromIndex: Int, toIndex: Int) {
    val xs = arrayOf("a", "b", "c")
    try {
        xs.fill("x", fromIndex, toIndex)
        println("ok:$fromIndex:$toIndex")
    } catch (e: IllegalArgumentException) {
        println("order:${e.message}")
    } catch (e: ArrayIndexOutOfBoundsException) {
        println("bounds:${e.message}")
    }
    println(xs.toList())
}

fun main() {
    val xs = arrayOf<Any?>("a", "b", "c", "d")
    clear(xs)
    println(xs.toList())
    xs.fill(element = "x", fromIndex = 1, toIndex = 3)
    println(xs.toList())
    xs.fill(null, fromIndex = 2)
    println(xs.toList())
    xs.fill("y", toIndex = 2)
    println(xs.toList())
    xs.fill("z", 2, 2)
    println(xs.toList())
    xs.fill("all")
    println(xs.toList())
    xs.fill(element = null)
    println(xs.toList())
    val strings = arrayOf("a", "b", "c")
    fillContravariant(strings)
    fillGeneric(strings, "generic")
    println(strings.toList())
    val ints = arrayOf(1, 2, 3)
    ints.fill(9, 1, 2)
    println(ints.toList())
    val primitive = intArrayOf(1, 2, 3)
    primitive.fill(9, 1, 2)
    println(primitive.toList())
    val empty = arrayOf<String>()
    empty.fill("unused")
    println(empty.toList())
    val tail = Array<Any?>(32) { "tail" }
    val root = Array<Any?>(32) { "root" }
    clearVectorBuffers(tail, root, 2, 0, 4)
    println(listOf(tail[0], tail[1], tail[2], tail[31]))
    println(listOf(root[0], root[1], root[31]))
    // Existing accepted controls from the issue.
    for (i in 1 until 2) xs[i] = "indexed"
    println(xs.toList())
    val largest = listOf(mutableListOf("a"), mutableListOf("b", "c")).maxBy { it.size }
    println(largest)
    checkRange(0, 0)
    checkRange(3, 3)
    checkRange(2, 1)
    checkRange(-1, 2)
    checkRange(0, 4)
    checkRange(-1, -1)
    checkRange(4, 4)
    checkRange(-1, -2)
    checkRange(4, 3)
}
