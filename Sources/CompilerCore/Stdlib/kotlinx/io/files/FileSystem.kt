/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 *
 * Derived from kotlinx-io core/common/src/files/FileSystem.kt (tag 0.9.1).
 * FileSource/FileSink below are derived from core/native/src/files/PathsNative.kt, with the
 * buffer plumbing of core/jvm/src/JvmCore.kt (UnsafeBufferOperations writeToTail/readFromHead).
 */
package kotlinx.io.files

import kotlin.internal.KsSymbolName
import kotlinx.io.Buffer
import kotlinx.io.RawSink
import kotlinx.io.RawSource
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.UnsafeBufferOperations

public sealed interface FileSystem {
    public fun exists(path: Path): Boolean
    public fun delete(path: Path, mustExist: Boolean = true)
    public fun createDirectories(path: Path, mustCreate: Boolean = false)
    public fun atomicMove(source: Path, destination: Path)
    public fun source(path: Path): RawSource
    public fun sink(path: Path, append: Boolean = false): RawSink
    public fun metadataOrNull(path: Path): FileMetadata?
    public fun resolve(path: Path): Path
    public fun list(directory: Path): Collection<Path>
}

public object SystemFileSystem : FileSystem {
    override fun exists(path: Path): Boolean = ioFsExists(path.toString())

    override fun delete(path: Path, mustExist: Boolean) {
        ioFsDelete(path.toString(), mustExist)
    }

    override fun createDirectories(path: Path, mustCreate: Boolean) {
        ioFsCreateDirectories(path.toString(), mustCreate)
    }

    override fun atomicMove(source: Path, destination: Path) {
        ioFsAtomicMove(source.toString(), destination.toString())
    }

    override fun source(path: Path): RawSource = FileSource(ioFsOpenRead(path.toString()))

    override fun sink(path: Path, append: Boolean): RawSink =
        FileSink(ioFsOpenWrite(path.toString(), append))

    override fun metadataOrNull(path: Path): FileMetadata? {
        val fields = ioFsMetadata(path.toString()) ?: return null
        return FileMetadata(fields[0] != 0L, fields[1] != 0L, fields[2])
    }

    override fun resolve(path: Path): Path = Path(ioFsResolve(path.toString()))

    override fun list(directory: Path): Collection<Path> {
        val result = mutableListOf<Path>()
        for (name in ioFsList(directory.toString())) {
            result.add(Path(directory, name))
        }
        return result
    }
}

public class FileMetadata(
    public val isRegularFile: Boolean = false,
    public val isDirectory: Boolean = false,
    public val size: Long = 0L
)

// Posix-backed RawSource over a file descriptor. Reads land in the sink's tail segment
// (matching upstream's InputStreamSource granularity), so a single call returns at most
// the current tail's remaining capacity. Closed descriptors read as `IOException`
// ("Stream Closed") via the bridge.
@OptIn(UnsafeIoApi::class)
private class FileSource(private var fd: Int) : RawSource {
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (byteCount == 0L) return 0L
        if (byteCount < 0L) throw IllegalArgumentException("byteCount ($byteCount) < 0")
        val written = UnsafeBufferOperations.writeToTail(sink, 1) { data, startIndex, endIndex ->
            val available = endIndex - startIndex
            val request = if (byteCount < available.toLong()) byteCount.toInt() else available
            val n = ioFsReadInto(fd, data, startIndex, request)
            if (n <= 0) 0 else n
        }
        return if (written == 0) -1L else written.toLong()
    }

    override fun close() {
        val descriptor = fd
        fd = -1
        if (descriptor >= 0) {
            ioFsClose(descriptor)
        }
    }

    override fun toString(): String = "FileSource($fd)"
}

// Posix-backed RawSink over a file descriptor. write() is unbuffered, so flush() is a
// no-op (matching JVM FileOutputStream.flush()).
@OptIn(UnsafeIoApi::class)
private class FileSink(private var fd: Int) : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        if (byteCount < 0L || source.size < byteCount) {
            throw IllegalArgumentException(
                "offset (0) and byteCount ($byteCount) are not within the range [0..size(${source.size}))"
            )
        }
        var remaining = byteCount
        while (remaining > 0L) {
            val consumed = UnsafeBufferOperations.readFromHead(source) { data, startIndex, endIndex ->
                val available = endIndex - startIndex
                val toCopy = if (remaining < available.toLong()) remaining.toInt() else available
                ioFsWrite(fd, data, startIndex, toCopy)
                toCopy
            }
            if (consumed <= 0) break
            remaining -= consumed.toLong()
        }
    }

    override fun flush() {}

    override fun close() {
        val descriptor = fd
        fd = -1
        if (descriptor >= 0) {
            ioFsClose(descriptor)
        }
    }

    override fun toString(): String = "FileSink($fd)"
}

@KsSymbolName("__kk_io_fs_exists")
private external fun ioFsExists(path: String): Boolean

@KsSymbolName("__kk_io_fs_delete")
private external fun ioFsDelete(path: String, mustExist: Boolean)

@KsSymbolName("__kk_io_fs_create_directories")
private external fun ioFsCreateDirectories(path: String, mustCreate: Boolean)

@KsSymbolName("__kk_io_fs_atomic_move")
private external fun ioFsAtomicMove(source: String, destination: String)

@KsSymbolName("__kk_io_fs_metadata")
private external fun ioFsMetadata(path: String): LongArray?

@KsSymbolName("__kk_io_fs_list")
private external fun ioFsList(path: String): List<String>

@KsSymbolName("__kk_io_fs_resolve")
private external fun ioFsResolve(path: String): String

@KsSymbolName("__kk_io_fs_open_read")
private external fun ioFsOpenRead(path: String): Int

@KsSymbolName("__kk_io_fs_open_write")
private external fun ioFsOpenWrite(path: String, append: Boolean): Int

@KsSymbolName("__kk_io_fs_read")
private external fun ioFsReadInto(fd: Int, dst: ByteArray, dstOffset: Int, byteCount: Int): Int

@KsSymbolName("__kk_io_fs_write")
private external fun ioFsWrite(fd: Int, src: ByteArray, srcOffset: Int, byteCount: Int)

@KsSymbolName("__kk_io_fs_close")
private external fun ioFsClose(fd: Int)
