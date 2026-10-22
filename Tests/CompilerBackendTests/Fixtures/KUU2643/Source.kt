package kotlinx.io

interface Buffer {
    val size: Long
    operator fun get(index: Long): Byte
}

interface Source {
    val buffer: Buffer
    fun require(byteCount: Long)
    fun indexOf(value: Byte, fromIndex: Long, toIndex: Long): Long
    fun readString(byteCount: Long): String
    fun skip(byteCount: Long)
    fun request(byteCount: Long): Boolean
}

class EOFException : RuntimeException()
