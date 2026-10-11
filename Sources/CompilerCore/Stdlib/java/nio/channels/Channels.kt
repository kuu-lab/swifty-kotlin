package java.nio.channels

import java.nio.ByteBuffer

public interface Channel : AutoCloseable {
    public fun isOpen(): Boolean
    @get:kotlin.jvm.JvmName("isOpen")
    public val isOpen: Boolean get() = isOpen()
    override fun close()
}
public interface ReadableByteChannel : Channel {
    public fun read(destination: ByteBuffer): Int
}
public interface WritableByteChannel : Channel {
    public fun write(source: ByteBuffer): Int
}
public interface ByteChannel : ReadableByteChannel, WritableByteChannel
