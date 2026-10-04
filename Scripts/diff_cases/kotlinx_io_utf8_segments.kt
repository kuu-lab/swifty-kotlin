import kotlinx.io.*

fun main() {
    var split = 1
    while (split < 4) {
        val buffer = Buffer()
        val padding = 8192 - split
        var i = 0
        while (i < padding) {
            buffer.writeByte(65)
            i += 1
        }
        buffer.writeString("😀€é\nrest")
        val copied = buffer.copy()
        val text = buffer.readString(padding.toLong() + 9L)
        println(text.length == padding + 4)
        println(text.substring(padding) == "😀€é")
        println(buffer.readLine() == "")
        println(buffer.readString() == "rest")
        copied.skip(padding.toLong())
        val source: Source = copied.peek()
        println(source.readString() == "😀€é\nrest")
        println(copied.readString() == "😀€é\nrest")
        split += 1
    }

    val buffer = Buffer()
    var i = 0
    while (i < 8191) {
        buffer.writeByte(65)
        i += 1
    }
    buffer.write(byteArrayOf(0xe2.toByte(), 0x82.toByte(), 65), 0, 3)
    val text = buffer.readString()
    println(text.length)
    println(text[8191].code)
    println(text[8192].code)
    println(buffer.size)
}
