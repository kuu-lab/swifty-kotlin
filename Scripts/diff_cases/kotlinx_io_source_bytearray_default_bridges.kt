// Directly exercises the Source.readAtMostTo$default and SourcesKt.readTo$default call sites.
import kotlinx.io.Buffer
import kotlinx.io.Source
import kotlinx.io.readTo

private fun sourceOf(vararg bytes: Byte): Source {
    val buffer = Buffer()
    buffer.write(bytes, 0, bytes.size)
    return buffer
}

private fun render(bytes: ByteArray): String = bytes.joinToString(",") { it.toInt().toString() }

fun main() {
    val atMostBothDefaults = sourceOf(10, 20, 30)
    val atMostBothTarget = byteArrayOf(99, 99, 99, 99)
    println("${atMostBothDefaults.readAtMostTo(atMostBothTarget)}:${render(atMostBothTarget)}")
    println("${atMostBothDefaults.readAtMostTo(atMostBothTarget)}:${render(atMostBothTarget)}")

    val atMostEndDefaultTarget = byteArrayOf(99, 99, 99, 99, 99)
    val atMostEndDefault = sourceOf(1, 2, 3)
    println("${atMostEndDefault.readAtMostTo(atMostEndDefaultTarget, startIndex = 2)}:${render(atMostEndDefaultTarget)}")

    val atMostStartDefaultTarget = byteArrayOf(99, 99, 99, 99)
    val atMostStartDefault = sourceOf(4, 5, 6)
    println("${atMostStartDefault.readAtMostTo(atMostStartDefaultTarget, endIndex = 2)}:${render(atMostStartDefaultTarget)}")

    val readToBothTarget = byteArrayOf(99, 99)
    sourceOf(7, 8).readTo(readToBothTarget)
    println(render(readToBothTarget))

    val readToEndDefaultTarget = byteArrayOf(99, 99, 99, 99, 99, 99)
    sourceOf(11, 12, 13, 14).readTo(readToEndDefaultTarget, startIndex = 2)
    println(render(readToEndDefaultTarget))

    val readToStartDefaultTarget = byteArrayOf(99, 99, 99, 99, 99)
    sourceOf(21, 22, 23).readTo(readToStartDefaultTarget, endIndex = 3)
    println(render(readToStartDefaultTarget))

    val partialTarget = byteArrayOf(0, 0, 0)
    try {
        sourceOf(41, 42).readTo(partialTarget)
        println("eof:missing")
    } catch (_: java.io.EOFException) {
        println("eof:${render(partialTarget)}")
    }

    try {
        sourceOf(51, 52, 53).readTo(ByteArray(3), startIndex = -1)
        println("bounds:missing")
    } catch (_: IndexOutOfBoundsException) {
        println("bounds:IndexOutOfBoundsException")
    }

    try {
        sourceOf(61).readAtMostTo(ByteArray(4), startIndex = 4, endIndex = 1)
        println("atMostOrder:missing")
    } catch (_: IllegalArgumentException) {
        println("atMostOrder:IllegalArgumentException")
    }

    try {
        sourceOf(62).readAtMostTo(ByteArray(4), startIndex = 1, endIndex = 5)
        println("atMostUpper:missing")
    } catch (_: IndexOutOfBoundsException) {
        println("atMostUpper:IndexOutOfBoundsException")
    }

    try {
        sourceOf(63).readAtMostTo(ByteArray(4), startIndex = -1, endIndex = 2)
        println("atMostLower:missing")
    } catch (_: IndexOutOfBoundsException) {
        println("atMostLower:IndexOutOfBoundsException")
    }

    try {
        sourceOf(64).readTo(ByteArray(3), startIndex = 2, endIndex = 0)
        println("readToOrder:missing")
    } catch (_: IllegalArgumentException) {
        println("readToOrder:IllegalArgumentException")
    }

    try {
        sourceOf(65).readTo(ByteArray(3), startIndex = -1)
        println("readToLower:missing")
    } catch (_: IndexOutOfBoundsException) {
        println("readToLower:IndexOutOfBoundsException")
    }

    try {
        sourceOf(66).readTo(ByteArray(3), endIndex = 4)
        println("readToUpper:missing")
    } catch (_: IndexOutOfBoundsException) {
        println("readToUpper:IndexOutOfBoundsException")
    }
}
