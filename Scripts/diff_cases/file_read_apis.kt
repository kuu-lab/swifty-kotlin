import java.io.File

// KUU-4077: kotlin.io File read-family extensions (readBytes, charset-aware
// readLines / forEachLine / useLines) and kotlin.text.charset() must resolve
// and match the JVM bundled stdlib. The fixture is written through
// File.outputStream() so the case is self-contained.
fun main() {
    val path = "/tmp/kswiftk_file_read_apis.txt"
    File(path).outputStream().use { it.write("alpha\nbeta\n".toByteArray()) }
    val file = File(path)

    println(file.readBytes().size)
    println(file.readBytes().toString(Charsets.UTF_8).trim())
    println(file.readText().trim())
    println(file.readLines())
    println(file.readLines(Charsets.US_ASCII))
    file.forEachLine(Charsets.US_ASCII) { println("L:$it") }
    println(file.useLines(Charsets.UTF_8) { it.count() })

    println(charset("UTF-8"))
    println(kotlin.text.charset("US-ASCII"))
    println("ascii".toByteArray(charset("ASCII")).size)

    // The charset argument must reach the decoder: a Latin-1 fixture reads
    // as café under ISO_8859_1 and as mojibake under the UTF-8 default.
    val latin1Path = "/tmp/kswiftk_file_read_apis_latin1.txt"
    File(latin1Path).outputStream().use {
        it.write(byteArrayOf(0x63, 0x61, 0x66, 0xE9.toByte()))
    }
    println(File(latin1Path).readText(Charsets.ISO_8859_1))
    println(File(latin1Path).readLines(Charsets.ISO_8859_1).size)

    try {
        File("/tmp/kswiftk_file_read_apis_missing.txt").readBytes()
        println("missing: not thrown")
    } catch (failure: java.io.FileNotFoundException) {
        println("missing: FileNotFoundException")
    }
    try {
        charset("NO-SUCH-CHARSET")
        println("charset: not thrown")
    } catch (failure: java.nio.charset.UnsupportedCharsetException) {
        println("charset: UnsupportedCharsetException")
    }
}
