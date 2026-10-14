// JAVA_FLAGS: -Dfile.encoding=UTF-8
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.Charset

// Kotlox uses this named argument; keep its binding without reading a file.
fun kotloxRead(file: File): String = file.readText(charset = Charset.defaultCharset())

// Reference parity requires a UTF-8 JVM default; native always uses UTF-8.
fun main() {
    val charset: Charset = Charset.defaultCharset()
    println(charset.name())
    println(charset === Charset.defaultCharset())
    println(charset === Charsets.UTF_8)
    println(charset === Charset.forName("utf8"))
    val erased: Any = charset
    println(erased is Charset)
    val nullable: Charset? = charset
    println(nullable?.name())

    val text = "hé日本😀"
    val bytes = text.toByteArray(charset)
    println(bytes.contentToString())
    println(bytes.contentEquals(text.toByteArray()))
    println(bytes.toString(charset))
    // Klox uses this String constructor with defaultCharset().
    println(String(bytes, Charset.defaultCharset()))
    println(text.byteInputStream(charset).bufferedReader().readText())
    println(text.byteInputStream().bufferedReader(charset).readText())

    val output = ByteArrayOutputStream()
    val writer = output.bufferedWriter(charset)
    writer.write(text)
    writer.flush()
    println(output.toByteArray().contentEquals(bytes))
    println(output.toString(charset))

    // Keep explicit non-default codecs as controls.
    val latin = Charset.forName("ISO-8859-1")
    println(latin.name())
    println("é".toByteArray(latin).contentToString())
    println("é".toByteArray(latin).toString(latin))
    println(Charsets.UTF_16BE.name())
}
