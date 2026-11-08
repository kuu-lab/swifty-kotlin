package java.io

public class PipedWriter protected constructor(pipeSize: Int) : Writer() {
    internal var channel: PipedChannel? = null
        private set
    internal var connected: Boolean = false
        private set
    private var closed: Boolean = false

    init {
        if (pipeSize <= 0) throw IllegalArgumentException("Pipe size <= 0")
    }

    public constructor() : this(PipedReader.DEFAULT_PIPE_SIZE)

    public constructor(reader: PipedReader) : this(PipedReader.DEFAULT_PIPE_SIZE) {
        connect(reader)
    }

    public fun connect(reader: PipedReader) {
        if (connected) throw IOException("Already connected")
        reader.attachWriter(this)
    }

    internal fun attachTo(reader: PipedReader) {
        if (connected) throw IOException("Already connected")
        reader.attachWriter(this)
    }

    internal fun bind(channel: PipedChannel) {
        this.channel = channel
        connected = true
    }

    public fun write(value: Int): Unit {
        val ch = connectedChannel()
        writeToChannel(ch, value.toChar())
    }

    public fun write(value: CharArray): Unit = write(value, 0, value.size)

    public fun write(value: CharArray, offset: Int, length: Int): Unit {
        val ch = connectedChannel()
        if (offset < 0 || length < 0 || offset > value.size - length) {
            throw IndexOutOfBoundsException(
                "Range [$offset, $offset + $length) out of bounds for length ${value.size}"
            )
        }
        writeToChannel(ch, value, offset, length)
    }

    public override fun write(value: String): Unit = write(value, 0, value.length)

    public fun write(value: String, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.length - length) {
            throw StringIndexOutOfBoundsException(
                "Range [$offset, ${offset + length}) out of bounds for length ${value.length}"
            )
        }
        val chars = CharArray(length)
        var index = 0
        while (index < length) {
            chars[index] = value[offset + index]
            index += 1
        }
        val ch = connectedChannel()
        writeToChannel(ch, chars, 0, length)
    }

    private fun writeToChannel(ch: PipedChannel, c: Char): Unit {
        while (true) {
            var wrote = false
            ch.guard.lock()
            try {
                if (closed || ch.readerClosed) throw IOException("Pipe closed")
                wrote = ch.size < ch.capacity
                if (wrote) {
                    ch.chars[ch.tail] = c
                    ch.tail = (ch.tail + 1) % ch.capacity
                    ch.size += 1
                }
            } finally {
                ch.guard.unlock()
            }
            if (wrote) {
                ch.signalReaders()
                return
            }
            ch.awaitSpace()
        }
    }

    private fun writeToChannel(ch: PipedChannel, value: CharArray, offset: Int, length: Int): Unit {
        var index = offset
        val end = offset + length
        while (index < end) {
            var wrote = false
            ch.guard.lock()
            try {
                if (closed || ch.readerClosed) throw IOException("Pipe closed")
                wrote = ch.size < ch.capacity
                if (wrote) {
                    ch.chars[ch.tail] = value[index]
                    ch.tail = (ch.tail + 1) % ch.capacity
                    ch.size += 1
                    index += 1
                }
            } finally {
                ch.guard.unlock()
            }
            if (wrote) {
                ch.signalReaders()
            } else {
                ch.awaitSpace()
            }
        }
    }

    private fun connectedChannel(): PipedChannel {
        val ch = channel
        if (!connected || ch == null) throw IOException("Pipe not connected")
        return ch
    }

    public override fun flush(): Unit {}

    public override fun close(): Unit {
        closed = true
        channel?.let {
            it.writerClosed = true
            it.signalAll()
        }
    }
}
