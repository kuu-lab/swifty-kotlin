import java.io.ByteArrayOutputStream
import kotlinx.io.Buffer
import kotlinx.io.copyTo
import kotlinx.io.readTo

fun bufferOf(value: String): Buffer {
    val buffer = Buffer()
    val bytes = value.encodeToByteArray()
    buffer.write(bytes, 0, bytes.size)
    return buffer
}

fun textOf(output: ByteArrayOutputStream): String = String(output.toByteArray())

fun main() {
    // KUU-2637 / jvm-6474dd39fbc52ecd: both range defaults are omitted.
    val copyAll = bufferOf("abcdef")
    val copyAllOutput = ByteArrayOutputStream()
    copyAll.copyTo(copyAllOutput)
    println("copy-all=${textOf(copyAllOutput)}")
    println("copy-all-size=${copyAll.size}")

    // KUU-2637 / jvm-6474dd39fbc52ecd: endIndex is omitted.
    val copyFromStart = bufferOf("abcdef")
    val copyFromStartOutput = ByteArrayOutputStream()
    copyFromStart.copyTo(copyFromStartOutput, startIndex = 2L)
    println("copy-start=${textOf(copyFromStartOutput)}")
    println("copy-start-size=${copyFromStart.size}")

    // KUU-2637 / jvm-6474dd39fbc52ecd: startIndex is omitted.
    val copyToEnd = bufferOf("abcdef")
    val copyToEndOutput = ByteArrayOutputStream()
    copyToEnd.copyTo(copyToEndOutput, endIndex = 3L)
    println("copy-end=${textOf(copyToEndOutput)}")
    println("copy-end-size=${copyToEnd.size}")

    val emptyCopy = Buffer()
    val emptyCopyOutput = ByteArrayOutputStream()
    emptyCopy.copyTo(emptyCopyOutput)
    println("copy-empty=${textOf(emptyCopyOutput)}")
    println("copy-empty-size=${emptyCopy.size}")

    // KUU-2637 / jvm-7ea1f3d4aa2ff9ba: byteCount is omitted.
    val readAll = bufferOf("uvwxyz")
    val readAllOutput = ByteArrayOutputStream()
    readAll.readTo(readAllOutput)
    println("read-all=${textOf(readAllOutput)}")
    println("read-all-size=${readAll.size}")

    val emptyRead = bufferOf("xyz")
    val emptyReadOutput = ByteArrayOutputStream()
    emptyRead.readTo(emptyReadOutput, 0L)
    println("read-zero=${textOf(emptyReadOutput)}")
    println("read-zero-size=${emptyRead.size}")

    val negativeRead = bufferOf("abc")
    try {
        negativeRead.readTo(ByteArrayOutputStream(), -1L)
        println("read-negative=no-throw")
    } catch (error: IllegalArgumentException) {
        println("read-negative=IllegalArgumentException")
    }

    val oversizedRead = bufferOf("abc")
    try {
        oversizedRead.readTo(ByteArrayOutputStream(), 4L)
        println("read-oversized=no-throw")
    } catch (error: IllegalArgumentException) {
        println("read-oversized=IllegalArgumentException")
    }

    val negativeStart = bufferOf("abc")
    try {
        negativeStart.copyTo(ByteArrayOutputStream(), startIndex = -1L)
        println("copy-negative-start=no-throw")
    } catch (error: IndexOutOfBoundsException) {
        println("copy-negative-start=IndexOutOfBoundsException")
    }

    val oversizedEnd = bufferOf("abc")
    try {
        oversizedEnd.copyTo(ByteArrayOutputStream(), endIndex = 4L)
        println("copy-oversized-end=no-throw")
    } catch (error: IndexOutOfBoundsException) {
        println("copy-oversized-end=IndexOutOfBoundsException")
    }

    val reversedRange = bufferOf("abc")
    try {
        reversedRange.copyTo(ByteArrayOutputStream(), startIndex = 2L, endIndex = 1L)
        println("copy-reversed-range=no-throw")
    } catch (error: IllegalArgumentException) {
        println("copy-reversed-range=IllegalArgumentException")
    }
}
