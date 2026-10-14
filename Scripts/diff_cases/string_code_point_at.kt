// KUU-2038: String.codePointAt uses UTF-16 indices, including malformed pairs.
import java.lang.StringIndexOutOfBoundsException

fun codePoint(text: String, offset: Int): Int = text.codePointAt(offset)
fun firstCodeUnit(text: String): Int = text[0].code
fun clear(builder: StringBuilder) { builder.delete(0, builder.length) }

fun String.implicitCodePoint(offset: Int): Int = codePointAt(offset)

// Compile-only coverage for xenocom Text.kt's nested implicit extension receiver.
// Its runtime receiver capture is tracked separately by KUU-2050. Character.charCount
// belongs to a separate issue, so advancing the iterator uses the returned value.
fun String.codePointSequence(): Sequence<Int> = object : Sequence<Int> {
    private val length = this@codePointSequence.length
    override fun iterator() = object : Iterator<Int> {
        private var offset = 0
        override fun hasNext(): Boolean = offset < length
        override fun next(): Int {
            if (offset < length) {
                val codePoint = codePointAt(offset)
                offset += if (codePoint >= 0x10000) 2 else 1
                return codePoint
            } else {
                throw NoSuchElementException()
            }
        }
    }
}

// Execute iteration on the String receiver itself; anonymous-object capture
// is covered only by compilation above until KUU-2050 is fixed.
fun String.printCodePoints() {
    var offset = 0
    while (offset < length) {
        val point = codePointAt(offset)
        println(point)
        offset += if (point >= 0x10000) 2 else 1
    }
}

fun bounds(text: String, index: Int) {
    try {
        println(codePoint(text, index))
    } catch (e: StringIndexOutOfBoundsException) {
        println("StringIndexOutOfBoundsException")
    } catch (e: IndexOutOfBoundsException) {
        println("IndexOutOfBoundsException")
    }
}

fun main() {
    val text = "A\u0000\u0301\uD83D\uDE00\uD800x\uDC00\uDBFF\uDFFF\uD800"
    for (index in 0 until text.length) println(codePoint(text, index))
    println("\uD800\uDC00".codePointAt(0))
    println("\uFFFF".codePointAt(0))
    println("\uDC00\uD800".codePointAt(0))
    println("\uD800\uD800".codePointAt(0))
    println(text.implicitCodePoint(3))
    "A\uD83D\uDE00B".printCodePoints()
    try {
        emptyList<Int>().iterator().next()
    } catch (e: NoSuchElementException) {
        println("NoSuchElementException")
    }
    bounds(text, -1)
    bounds(text, text.length)
    bounds(text, text.length + 1)
    bounds("", 0)
    bounds(text, Int.MIN_VALUE)
    bounds(text, Int.MAX_VALUE)
    println(firstCodeUnit("\uD83D\uDE00"))
    val builder = StringBuilder("abc")
    clear(builder)
    println(builder.length)
}
