package io.bytestring.shape.consumer

import io.bytestring.shape.producer.asComparable
import io.bytestring.shape.producer.byteStringCompanion
import kotlinx.io.bytestring.ByteString

fun main() {
    val value = ByteString(1.toByte(), 2.toByte())
    val comparable: Comparable<ByteString> = asComparable(value)
    val other = ByteString(1.toByte(), 3.toByte())
    println("ByteString.compareTo:" + comparable.compareTo(other))

    val returnedCompanion: ByteString.Companion = byteStringCompanion()
    val directCompanion: ByteString.Companion = ByteString.Companion
    println("ByteString.Companion.public-type:true")
    println("ByteString.Companion.singleton:" + (returnedCompanion === directCompanion))
}
