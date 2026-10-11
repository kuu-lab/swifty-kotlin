@file:Suppress("DEPRECATION_ERROR")
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.channels.ClosedChannelException
import java.nio.channels.NonReadableChannelException
import java.nio.channels.NonWritableChannelException
import java.nio.file.Paths
import java.nio.file.StandardOpenOption
import kotlin.io.path.createFile
import kotlin.io.path.inputStream
import kotlinx.io.*
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.files.Path as IoPath

private fun fileChannelFailure(block: () -> Unit): String = try { block(); "none" } catch(e: Exception) {
    when(e) {
        is ClosedChannelException -> "Closed"
        is NonReadableChannelException -> "NonReadable"
        is NonWritableChannelException -> "NonWritable"
        is IllegalArgumentException -> "Argument"
        else -> throw e
    }
}
public fun runFileChannelProducerProbe() {
    val root = kotlin.io.createTempDir()
    val file = Paths.get(root.path, "channel").createFile()
    try {
        val writer = FileChannel.open(file, StandardOpenOption.WRITE)
        val data = ByteBuffer.allocate(1024)
        data.put("abcdefghijklmnopqrstuvwxyz".toByteArray(Charsets.UTF_8))
        data.flip().position(3).limit(23)
        println("file-channel-write:${writer.write(data)}/${data.position()}/${data.limit()}")
        println("file-channel-write-zero:${writer.write(ByteBuffer.allocate(0))}")
        println("file-channel-nonreadable:${fileChannelFailure { writer.read(ByteBuffer.allocate(1)) }}")
        writer.close()
        println("file-channel-write-closed:${writer.isOpen()}/${fileChannelFailure { writer.write(ByteBuffer.allocate(0)) }}")
        val source = file.inputStream().asSource().buffered()
        println("file-channel-written:${source.readString()}")
        source.close()
        val reader = FileChannel.open(file, StandardOpenOption.READ)
        val destination = ByteBuffer.allocate(1024).position(3).limit(23)
        println("file-channel-read:${reader.read(destination)}/${destination.position()}/${destination.limit()}")
        destination.flip().position(3)
        val bytes = ByteArray(destination.remaining())
        destination[bytes]
        println("file-channel-read-data:${String(bytes, Charsets.UTF_8)}")
        println("file-channel-read-zero-at-eof:${reader.read(ByteBuffer.allocate(0))}")
        println("file-channel-read-eof:${reader.read(ByteBuffer.allocate(1))}")
        println("file-channel-readonly:${fileChannelFailure { reader.read(ByteBuffer.allocate(0).asReadOnlyBuffer()) }}")
        println("file-channel-nonwritable:${fileChannelFailure { reader.write(ByteBuffer.allocate(0)) }}")
        reader.close()
        println("file-channel-read-closed:${reader.isOpen()}/${fileChannelFailure { reader.read(ByteBuffer.allocate(0).asReadOnlyBuffer()) }}")
    } finally {
        SystemFileSystem.delete(IoPath(file.toString()))
        SystemFileSystem.delete(IoPath(root.path))
    }
}
