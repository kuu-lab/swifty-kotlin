fun main() {
    val s = buildString {
        appendRange("Hello, World!", 0, 5)
        append(" ")
        appendRange("Hello, World!", 7, 13)
    }
    println(s)

    // ASCII range slicing: basic start/end validation.
    val u = buildString {
        appendRange("ABCDE", 1, 4)
        append("|")
        appendRange("abcdef", 0, 3)
        append("|")
        appendRange("12345", 2, 5)
    }
    println(u)

    // CJK characters are single UTF-16 code units (BMP) but multi-byte in
    // UTF-8.  Slicing by UTF-16 index should differ from a naive byte index.
    val cjk = buildString {
        appendRange("\u4F60\u597D\u4E16\u754C", 1, 3)  // "好世" from "你好世界"
    }
    println(cjk)

    val source: CharSequence = StringBuilder("A\uD83D\uDE00B")
    val destination = StringBuilder(">")
    println(destination.appendRange(source, 1, 3) === destination)
    println(destination.toString())
    println(destination.appendRange(source, 4, 4) === destination)
    println(destination.toString())

    val self = StringBuilder("abcd")
    println(self.appendRange(self, 1, 3) === self)
    println(self.toString())

    val units = StringBuilder().appendRange(source, 1, 2)
    println(units.length)
    println(units[0].code)

    invalidRange(-1, 2)
    invalidRange(3, 2)
    invalidRange(0, 5)
    invalidRange(5, 5)
}

fun invalidRange(startIndex: Int, endIndex: Int) {
    val destination = StringBuilder("unchanged")
    val source: CharSequence = StringBuilder("abcd")
    try {
        destination.appendRange(source, startIndex, endIndex)
        println("unexpected success")
    } catch (e: IndexOutOfBoundsException) {
        println(destination.toString())
    }
}
