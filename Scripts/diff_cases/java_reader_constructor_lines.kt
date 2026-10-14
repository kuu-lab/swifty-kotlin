import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.SequenceInputStream

fun wrap(input: java.io.InputStream): BufferedReader = BufferedReader(InputStreamReader(input))
fun closeFromInterface(reader: AutoCloseable) { reader.close() }

fun main() {
    val stream = "!hello\n日本語\rα\r\nlast".byteInputStream()
    val decoder = InputStreamReader(stream)
    // Construction must not advance the input stream.
    println(stream.read())
    val reader = BufferedReader(decoder)
    println(reader.readLine())
    println(reader.readLine())
    println(reader.readLine())
    println(reader.readLine())
    println(reader.readLine())
    reader.close()
    reader.close()

    val empty = wrap("".byteInputStream())
    println(empty.readLine())
    empty.close()

    val nested = BufferedReader(wrap("ab\ntail".byteInputStream()))
    println(nested.read())
    println(nested.readLine())
    println(nested.readText())
    nested.close()

    val control = "control\n".byteInputStream().bufferedReader()
    println(control.readLine())
    println(control.readLine())
    control.close()
    println("control use\n".byteInputStream().bufferedReader().use { it.readLine() })

    println(wrap("use\n".byteInputStream()).use { it.readLine() })
    closeFromInterface(InputStreamReader("unread".byteInputStream()))
    println("erased")
    try {
        wrap("unread".byteInputStream()).use { throw IllegalStateException("block") }
    } catch (_: IllegalStateException) {
        println("use exception")
    }

    val chained = wrap(SequenceInputStream("a".byteInputStream(), "b\n日本語\n".byteInputStream()))
    println(chained.readLine())
    println(chained.readLine())
    println(chained.readLine())
    chained.close()

    val availability = SequenceInputStream("a".byteInputStream(), "bc".byteInputStream())
    availability.read()
    availability.read()
    println(availability.available())
    availability.close()
}
