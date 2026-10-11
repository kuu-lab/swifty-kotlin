package java.nio.channels

import java.nio.ByteBuffer
import java.nio.file.Path
import java.nio.file.OpenOption
import java.nio.file.StandardOpenOption
import java.nio.file.LinkOption
import kotlin.internal.KsSymbolName

public class ClosedChannelException : java.io.IOException()
public class NonReadableChannelException : IllegalStateException()
public class NonWritableChannelException : IllegalStateException()

/** Native sequential regular-file channel. Positional, mapped and locking APIs
 * are not represented by this source model. It supplies the original NioTest
 * producers without substituting Buffer for their FileChannel. */
public class FileChannel private constructor(
    private var descriptor: Int,
    private val readable: Boolean,
    private val writable: Boolean,
) : ByteChannel {
    override fun isOpen(): Boolean = descriptor >= 0
    override fun read(destination: ByteBuffer): Int {
        if (descriptor < 0) throw ClosedChannelException()
        if (!readable) throw NonReadableChannelException()
        if (destination.isReadOnly()) throw IllegalArgumentException("Read-only buffer")
        val count = destination.remaining()
        if (count == 0) return 0
        val bytes = ByteArray(count)
        val read = channelRead(descriptor, bytes, 0, count)
        if (read == 0) return -1
        destination.put(bytes, 0, read)
        return read
    }
    override fun write(source: ByteBuffer): Int {
        if (descriptor < 0) throw ClosedChannelException()
        if (!writable) throw NonWritableChannelException()
        val count = source.remaining()
        if (count == 0) return 0
        val bytes = ByteArray(count)
        source.duplicate().get(bytes)
        val written = channelWrite(descriptor, bytes, 0, count)
        source.position(source.position() + written)
        return written
    }
    override fun close() {
        val previous = descriptor
        descriptor = -1
        if (previous >= 0) channelClose(previous)
    }
    public companion object {
        public fun open(path: Path, vararg options: OpenOption): FileChannel {
            var flags = 0
            for (option in options) {
                flags = flags or when (option) {
                    StandardOpenOption.READ -> 1
                    StandardOpenOption.WRITE -> 2
                    StandardOpenOption.APPEND -> 4
                    StandardOpenOption.CREATE -> 8
                    StandardOpenOption.CREATE_NEW -> 16
                    StandardOpenOption.TRUNCATE_EXISTING -> 32
                    StandardOpenOption.DELETE_ON_CLOSE -> 64
                    StandardOpenOption.SYNC -> 128
                    StandardOpenOption.DSYNC -> 256
                    LinkOption.NOFOLLOW_LINKS -> 512
                    StandardOpenOption.SPARSE -> 0 // a permitted creation hint
                    else -> throw UnsupportedOperationException("Unsupported open option")
                }
            }
            val append = (flags and 4) != 0
            if (append) {
                if ((flags and 1) != 0 || (flags and 32) != 0) throw IllegalArgumentException("APPEND conflicts with READ/TRUNCATE_EXISTING")
                flags = flags or 2
            }
            if ((flags and 3) == 0) flags = flags or 1
            return FileChannel(channelOpen(path.toString(), flags), (flags and 1) != 0, (flags and 2) != 0)
        }
    }
}
@KsSymbolName("__kk_native_filechannel_open")
private external fun channelOpen(path: String, flags: Int): Int
@KsSymbolName("__kk_io_fs_read")
private external fun channelRead(descriptor: Int, bytes: ByteArray, offset: Int, count: Int): Int
@KsSymbolName("__kk_native_filechannel_write")
private external fun channelWrite(descriptor: Int, bytes: ByteArray, offset: Int, count: Int): Int
@KsSymbolName("__kk_io_fs_close")
private external fun channelClose(descriptor: Int)
