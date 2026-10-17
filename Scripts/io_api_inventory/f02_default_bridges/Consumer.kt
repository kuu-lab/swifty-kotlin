package io2624consumer

import io2624producer.*
import kotlinx.io.bytestring.ByteString

private fun bytes(value: ByteArray): String = value.joinToString(",")

private fun failureName(block: () -> Unit): String = try {
    block()
    "none"
} catch (_: IllegalArgumentException) {
    "IllegalArgumentException"
} catch (_: IndexOutOfBoundsException) {
    "IndexOutOfBoundsException"
}

fun main() {
    val value = ByteString(byteArrayOf(1, 2, 3, 4, 5, 6))
    println("toByteArray:all=" + bytes(toByteArrayAllDefaults(value)))
    println("toByteArray:start-default=" + bytes(toByteArrayDefaultStart(value)))
    println("toByteArray:end-default=" + bytes(toByteArrayDefaultEnd(value)))
    println("toByteArray:explicit=" + bytes(toByteArrayExplicit(value)))

    println("substring:end-default=" + bytes(substringDefaultEnd(value).toByteArray()))
    println("substring:explicit=" + bytes(substringExplicit(value).toByteArray()))

    val allDefaults = ByteArray(8)
    copyIntoAllDefaults(value, allDefaults)
    println("copyInto:all-defaults=" + bytes(allDefaults))
    val defaultOffset = ByteArray(8)
    copyIntoDefaultOffset(value, defaultOffset)
    println("copyInto:offset-default=" + bytes(defaultOffset))
    val defaultStart = ByteArray(8)
    copyIntoDefaultStart(value, defaultStart)
    println("copyInto:start-default=" + bytes(defaultStart))
    val defaultEnd = ByteArray(8)
    copyIntoDefaultEnd(value, defaultEnd)
    println("copyInto:end-default=" + bytes(defaultEnd))

    println("toByteArray:reversed=" + failureName { value.toByteArray(2, 1) })
    println("toByteArray:past-end=" + failureName { value.toByteArray(endIndex = 7) })
    println("substring:reversed=" + failureName { value.substring(2, 1) })
    println("substring:past-end=" + failureName { value.substring(0, 7) })
    println("copyInto:reversed=" + failureName { value.copyInto(ByteArray(8), startIndex = 2, endIndex = 1) })
    println("copyInto:destination-overflow=" + failureName { value.copyInto(ByteArray(4)) })
}
