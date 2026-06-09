package golden.sema

import java.io.File

fun writeWithBufferedWriter(path: String, text: String) {
    val file = File(path)
    file.bufferedWriter().use { writer ->
        writer.write(text)
        writer.newLine()
        writer.flush()
    }
}

fun appendWithBufferedWriter(path: String, line: String) {
    val file = File(path)
    val writer = file.bufferedWriter()
    writer.write(line)
    writer.newLine()
    writer.close()
}
