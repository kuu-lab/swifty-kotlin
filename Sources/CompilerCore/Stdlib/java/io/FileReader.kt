package java.io

public class FileReader : Reader {
    private val delegate: StringReader

    public constructor(file: File) {
        delegate = StringReader(file.readText())
    }

    public constructor(file: File, charset: Charset) {
        delegate = StringReader(file.readText(charset))
    }

    public constructor(fileName: String) {
        delegate = StringReader(File(fileName).readText())
    }

    public constructor(fileName: String, charset: Charset) {
        delegate = StringReader(File(fileName).readText(charset))
    }

    public fun read(): Int = delegate.read()

    public override fun read(buffer: CharArray, offset: Int, length: Int): Int =
        delegate.read(buffer, offset, length)

    public fun ready(): Boolean = delegate.ready()

    public fun skip(count: Long): Long = delegate.skip(count)

    public fun mark(readAheadLimit: Int): Unit = delegate.mark(readAheadLimit)

    public fun reset(): Unit = delegate.reset()

    public fun markSupported(): Boolean = true

    public override fun close(): Unit = delegate.close()
}
