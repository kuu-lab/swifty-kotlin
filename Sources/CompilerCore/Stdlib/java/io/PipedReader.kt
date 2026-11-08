@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.io

import java.util.concurrent.jucPark
import java.util.concurrent.jucUnparkAll
import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject

// Shared blocking pipe state for PipedReader/PipedWriter. The JDK keeps the
// circular char buffer on the reader side and guards it with the reader's
// monitor plus wait/notify; here the channel carries the buffer, a
// SynchronizedObject guard, and per-side parker wait lists using the same
// jucPark/jucUnparkAll plumbing as CountDownLatch.
internal class PipedChannel(val capacity: Int) {
    val guard = SynchronizedObject()
    val readWaiters = ArrayList<ParkingHandle>()
    val writeWaiters = ArrayList<ParkingHandle>()
    val chars = CharArray(capacity)
    var head: Int = 0
    var tail: Int = 0
    var size: Int = 0
    var writerClosed: Boolean = false
    var readerClosed: Boolean = false
}

internal fun PipedChannel.awaitData() {
    val handle = ParkingSupport.currentThreadHandle()
    guard.lock()
    try {
        readWaiters.add(handle)
    } finally {
        guard.unlock()
    }
    try {
        while (true) {
            guard.lock()
            try {
                if (size > 0 || writerClosed) {
                    readWaiters.remove(handle)
                    return
                }
                if (!readWaiters.contains(handle)) readWaiters.add(handle)
            } finally {
                guard.unlock()
            }
            jucPark(-1L)
        }
    } finally {
        guard.lock()
        try {
            readWaiters.remove(handle)
        } finally {
            guard.unlock()
        }
    }
}

internal fun PipedChannel.awaitSpace() {
    val handle = ParkingSupport.currentThreadHandle()
    guard.lock()
    try {
        writeWaiters.add(handle)
    } finally {
        guard.unlock()
    }
    try {
        while (true) {
            guard.lock()
            try {
                if (size < capacity || readerClosed) {
                    writeWaiters.remove(handle)
                    return
                }
                if (!writeWaiters.contains(handle)) writeWaiters.add(handle)
            } finally {
                guard.unlock()
            }
            jucPark(-1L)
        }
    } finally {
        guard.lock()
        try {
            writeWaiters.remove(handle)
        } finally {
            guard.unlock()
        }
    }
}

internal fun PipedChannel.signalReaders() {
    val wake: List<ParkingHandle>
    guard.lock()
    try {
        if (readWaiters.isEmpty()) return
        wake = ArrayList(readWaiters)
        readWaiters.clear()
    } finally {
        guard.unlock()
    }
    jucUnparkAll(wake)
}

internal fun PipedChannel.signalWriters() {
    val wake: List<ParkingHandle>
    guard.lock()
    try {
        if (writeWaiters.isEmpty()) return
        wake = ArrayList(writeWaiters)
        writeWaiters.clear()
    } finally {
        guard.unlock()
    }
    jucUnparkAll(wake)
}

internal fun PipedChannel.signalAll() {
    signalReaders()
    signalWriters()
}

public class PipedReader protected constructor(private val pipeSize: Int) : Reader() {
    internal var channel: PipedChannel? = null
        private set
    internal var connected: Boolean = false
        private set
    private var closed: Boolean = false

    init {
        if (pipeSize <= 0) throw IllegalArgumentException("Pipe size <= 0")
    }

    public constructor() : this(DEFAULT_PIPE_SIZE)

    public constructor(writer: PipedWriter) : this(DEFAULT_PIPE_SIZE) {
        connect(writer)
    }

    public fun connect(writer: PipedWriter) {
        if (connected) throw IOException("Already connected")
        writer.attachTo(this)
    }

    internal fun attachWriter(writer: PipedWriter) {
        connected = true
        val ch = PipedChannel(pipeSize)
        channel = ch
        writer.bind(ch)
    }

    public fun read(): Int {
        val buffer = CharArray(1)
        val count = read(buffer, 0, 1)
        return if (count <= 0) count else buffer[0].code
    }

    public override fun read(buffer: CharArray, offset: Int, length: Int): Int {
        val ch = connectedChannel()
        if (closed) throw IOException("Pipe closed")
        if (offset < 0 || length < 0 || offset > buffer.size - length) {
            throw IndexOutOfBoundsException(
                "Range [$offset, $offset + $length) out of bounds for length ${buffer.size}"
            )
        }
        if (length == 0) return 0

        ch.guard.lock()
        val hasData = ch.size > 0 || ch.writerClosed
        ch.guard.unlock()
        if (!hasData) ch.awaitData()
        if (closed) throw IOException("Pipe closed")

        ch.guard.lock()
        var copied = 0
        try {
            while (copied < length && ch.size > 0) {
                buffer[offset + copied] = ch.chars[ch.head]
                ch.head = (ch.head + 1) % ch.capacity
                ch.size -= 1
                copied += 1
            }
        } finally {
            ch.guard.unlock()
        }
        if (copied == 0) return -1
        ch.signalWriters()
        return copied
    }

    public fun ready(): Boolean {
        val ch = channel ?: return false
        ch.guard.lock()
        try {
            return ch.size > 0
        } finally {
            ch.guard.unlock()
        }
    }

    public fun skip(count: Long): Long {
        var remaining = count
        var skipped = 0L
        val buffer = CharArray(8192)
        while (remaining > 0L) {
            val chunk = minOf(remaining, buffer.size.toLong()).toInt()
            val n = read(buffer, 0, chunk)
            if (n <= 0) break
            skipped += n
            remaining -= n
        }
        return skipped
    }

    public fun mark(readAheadLimit: Int): Unit {}

    public fun reset(): Unit {
        throw IOException("Stream not marked")
    }

    public fun markSupported(): Boolean = false

    public override fun close(): Unit {
        closed = true
        channel?.let { it.readerClosed = true; it.signalAll() }
    }

    internal fun connectedChannel(): PipedChannel {
        val ch = channel
        if (!connected || ch == null) throw IOException("Pipe not connected")
        return ch
    }

    internal companion object {
        const val DEFAULT_PIPE_SIZE = 1024
    }
}
