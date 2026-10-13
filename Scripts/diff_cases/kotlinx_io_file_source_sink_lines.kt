import kotlinx.io.*
import kotlinx.io.files.*
import kotlin.random.Random

// Line-oriented coverage for file-backed RawSource/RawSink: the sibling
// kotlinx_io_filesystem_source_sink.kt case exercises byte/block reads, while
// this pins Source.readLine()/readLineStrict() and post-close access through
// SystemFileSystem (KSP-1559 / KUU-895).
fun main() {
    val fs: FileSystem = SystemFileSystem
    val root = Path(SystemTemporaryDirectory, "kswiftk-fs-lines-" + Random.nextInt(1, 1000000000))
    val lines = Path(root, "lines.txt")
    fs.createDirectories(root)
    try {
        // Mixed LF/CRLF without a trailing newline: last readLine() hits EOF.
        fs.sink(lines).buffered().use { sink ->
            sink.writeString("alpha\nbeta\r\ngamma")
        }
        fs.source(lines).buffered().use { source ->
            println(source.readLine())
            println(source.readLine())
            println(source.readLine())
            println(source.readLine())
        }

        // append = true extends existing content with another line.
        fs.sink(lines, append = true).buffered().use { it.writeString("\ndelta") }
        fs.source(lines).buffered().use { source ->
            var line = source.readLine()
            while (line != null) {
                println("L:" + line)
                line = source.readLine()
            }
        }

        // A trailing newline does not produce a phantom empty line.
        fs.sink(lines).buffered().use { it.writeString("x\n") }
        fs.source(lines).buffered().use { source ->
            println(source.readLine())
            println(source.readLine())
        }

        // An empty file is at EOF immediately.
        fs.sink(lines).buffered().use { }
        fs.source(lines).buffered().use { source ->
            println(source.readLine())
        }

        // readLineStrict throws EOFException when no terminator precedes EOF.
        fs.sink(lines).buffered().use { it.writeString("partial") }
        fs.source(lines).buffered().use { source ->
            try {
                source.readLineStrict()
            } catch (e: EOFException) {
                println("strict eof")
            }
        }
        fs.sink(lines).buffered().use { it.writeString("ok\n") }
        fs.source(lines).buffered().use { source ->
            println(source.readLineStrict())
        }

        // Reading a closed buffered source throws IllegalStateException, while a
        // closed raw file source throws IOException (matching FileInputStream).
        val closed = fs.source(lines).buffered()
        closed.close()
        try {
            closed.readLine()
        } catch (e: IllegalStateException) {
            println("closed")
        }
        val raw = fs.source(lines)
        raw.close()
        try {
            raw.readAtMostTo(Buffer(), 1)
        } catch (e: IOException) {
            println("raw closed")
        }
    } finally {
        fs.delete(lines, mustExist = false)
        fs.delete(root, mustExist = false)
    }
}
