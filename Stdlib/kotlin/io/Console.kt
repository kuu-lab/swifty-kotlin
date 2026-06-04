package kotlin.io

import kswiftk.internal.*

private const val STDOUT_FD = 1
private const val STDIN_FD = 0
private const val BUFFER_SIZE = 8192

private val writeBuffer = ByteArray(BUFFER_SIZE)
private var writeBufferPos = 0

private fun flush() {
    if (writeBufferPos > 0) {
        __sys_write(STDOUT_FD, writeBuffer, writeBufferPos)
        writeBufferPos = 0
    }
}

private fun writeBytes(bytes: ByteArray) {
    var offset = 0
    while (offset < bytes.size) {
        val remaining = BUFFER_SIZE - writeBufferPos
        val toWrite = minOf(remaining, bytes.size - offset)

        for (i in 0 until toWrite) {
            writeBuffer[writeBufferPos++] = bytes[offset++]
        }

        if (writeBufferPos >= BUFFER_SIZE) {
            flush()
        }
    }
}

fun println(): Unit {
    writeBytes("\n".toByteArray())
    flush()
}

fun println(message: Any?): Unit {
    // TODO: Implement string formatting in Kotlin (currently using runtime)
    if (message == null) {
        writeBytes("null".toByteArray())
    } else {
        writeBytes(message.toString().toByteArray())
    }
    writeBytes("\n".toByteArray())
    flush()
}

fun print(): Unit {
    // no-op
}

fun print(message: Any?): Unit {
    // TODO: Implement string formatting in Kotlin (currently using runtime)
    if (message == null) {
        writeBytes("null".toByteArray())
    } else {
        writeBytes(message.toString().toByteArray())
    }
}

fun readLine(): String? = readlnOrNull()

fun readln(): String {
    val line = readlnOrNull()
    return if (line == null) {
        throw IllegalStateException("EOF")
    } else {
        line
    }
}

fun readlnOrNull(): String? {
    // Note: Reading from stdin using system calls requires ByteArray to String conversion
    // which depends on runtime functions (kk_string_from_utf8). For now, we keep using
    // the runtime function for readln to avoid complex pointer manipulation in Kotlin.
    // The println/print functions now use system calls directly with buffering.
    return __readlnOrNull()
}
