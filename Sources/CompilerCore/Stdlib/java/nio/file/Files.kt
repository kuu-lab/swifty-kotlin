package java.nio.file

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_io_fs_open_read")
private external fun openRead(path: String): Int

@KsSymbolName("__kk_io_fs_read")
private external fun readInto(fd: Int, bytes: ByteArray, offset: Int, count: Int): Int

@KsSymbolName("__kk_io_fs_close")
private external fun closeRead(fd: Int)

@KsSymbolName("__kk_io_fs_exists")
private external fun pathExists(path: String): Boolean

public object Files {
    public fun exists(path: Path): Boolean = pathExists(path.toString())

    public fun readAllBytes(path: Path): ByteArray {
        val fd = openRead(path.toString())
        try {
            val chunks = mutableListOf<ByteArray>()
            val buffer = ByteArray(8192)
            var size = 0
            while (true) {
                val count = readInto(fd, buffer, 0, buffer.size)
                if (count == 0) break
                if (count > Int.MAX_VALUE - size) {
                    throw OutOfMemoryError("Required array size too large")
                }
                chunks.add(buffer.copyOf(count))
                size += count
            }
            val result = ByteArray(size)
            var offset = 0
            for (chunk in chunks) {
                chunk.copyInto(result, offset)
                offset += chunk.size
            }
            return result
        } finally {
            closeRead(fd)
        }
    }
}
