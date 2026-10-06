import kotlinx.io.*
import kotlinx.io.files.*
import kotlin.random.Random

fun main() {
    // Interface-typed dispatch, matching real call sites.
    val fs: FileSystem = SystemFileSystem
    val root = Path(SystemTemporaryDirectory, "kswiftk-fs-io-" + Random.nextInt(1, 1000000000))
    val textFile = Path(root, "text.txt")
    val binFile = Path(root, "data.bin")
    val missing = Path(root, "missing")
    val orphaned = Path(root, "no", "such", "dir", "file.bin")
    fs.createDirectories(root)
    try {
        // sink(path) creates the file; use on the buffered sink flushes on close.
        fs.sink(textFile).buffered().use { sink ->
            sink.writeString("hello")
            sink.write(ByteArray(3) { i -> (i + 1).toByte() })
            sink.flush()
        }
        fs.source(textFile).buffered().use { source ->
            println(source.readString(5))
            println(source.readByteArray().toList())
        }
        println(fs.metadataOrNull(textFile)?.size)

        // append = true extends; default append = false truncates.
        fs.sink(textFile, append = true).buffered().use { it.writeString("+") }
        println(fs.metadataOrNull(textFile)?.size)
        fs.sink(textFile).buffered().use { it.writeString("xy") }
        println(fs.metadataOrNull(textFile)?.size)
        fs.source(textFile).buffered().use { println(it.readString()) }

        // Binary round-trip through ByteArray (explicit inner param: nested implicit
        // `it` is mis-bound — KUU-1431).
        fs.sink(binFile).buffered().use { sink ->
            sink.write(ByteArray(4) { i -> (i * 7).toByte() })
        }
        fs.source(binFile).buffered().use { source ->
            println(source.readByte())
            println(source.readByteArray().toList())
        }

        // RawSource contract: 0 for a zero-length request, -1 at EOF.
        fs.source(textFile).use { raw ->
            val buffer = Buffer()
            println(raw.readAtMostTo(buffer, 0))
            println(raw.readAtMostTo(buffer, 10))
            println(buffer.readString())
            println(raw.readAtMostTo(buffer, 10))
            try {
                raw.readAtMostTo(buffer, -1)
            } catch (e: IllegalArgumentException) {
                println("negative byteCount")
            }
        }

        // Open failures surface as FileNotFoundException (JVM FileInputStream parity),
        // also catchable through the IOException supertype.
        try {
            fs.source(missing)
        } catch (e: FileNotFoundException) {
            println("missing source")
        }
        try {
            fs.source(root)
        } catch (e: FileNotFoundException) {
            println("directory source")
        }
        try {
            fs.sink(orphaned)
        } catch (e: FileNotFoundException) {
            println("orphaned sink")
        }
        try {
            fs.sink(root)
        } catch (e: FileNotFoundException) {
            println("directory sink")
        }
        try {
            fs.source(missing)
        } catch (e: IOException) {
            println("missing source as io")
        }

        // Operations after close throw IOException("Stream Closed"); close is idempotent.
        val closedSource = fs.source(textFile)
        closedSource.close()
        closedSource.close()
        try {
            closedSource.readAtMostTo(Buffer(), 1)
        } catch (e: IOException) {
            println("read after close")
        }
        val closedSink = fs.sink(textFile)
        closedSink.close()
        try {
            val pending = Buffer()
            pending.writeByte(1)
            closedSink.write(pending, 1)
        } catch (e: IOException) {
            println("write after close")
        }
    } finally {
        fs.delete(binFile, mustExist = false)
        fs.delete(textFile, mustExist = false)
        fs.delete(root, mustExist = false)
    }
}
