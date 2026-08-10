// A user-defined `size` / `isEmpty` property with a custom getter must be read
// through that getter even when referenced via the implicit receiver inside the
// declaring class. The built-in collection shortcuts (kk_collection_size /
// kk_collection_isEmpty) must not hijack the name.
class Window(private val count: Int) {
    val size: Int
        get() = count * 2

    val isEmpty: Boolean
        get() = count == 0

    fun readSize(): Int = size

    fun readIsEmpty(): Boolean = isEmpty

    fun describe(): String {
        if (isEmpty) {
            return "empty"
        }
        return "size=" + size
    }
}

// A getter-only property whose type is a range: the range expression is the
// whole getter body.
class Span(private val start: Int, private val length: Int) {
    val bounds: IntRange
        get() = start..(start + length - 1)

    fun firstIndex(): Int = bounds.first
}

fun main() {
    val window = Window(3)
    println(window.size)
    println(window.readSize())
    println(window.isEmpty)
    println(window.readIsEmpty())
    println(window.describe())

    val empty = Window(0)
    println(empty.readIsEmpty())
    println(empty.describe())

    val span = Span(4, 3)
    println(span.bounds.first)
    println(span.bounds.last)
    println(span.firstIndex())
}
