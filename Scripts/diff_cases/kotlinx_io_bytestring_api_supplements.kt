@file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)

import kotlinx.io.bytestring.*
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations
import kotlin.io.encoding.Base64

var evaluations = 0
fun bytesOnce(): ByteArray {
    evaluations++
    return byteArrayOf(1, 2, 3)
}

fun unsafeNonLocalReturn(): Int {
    UnsafeByteStringOperations.withByteArrayUnsafe(ByteString(7)) { return it[0].toInt() }
    return -1
}

fun constructorResult(start: Int, end: Int): String {
    return try {
        ByteString(byteArrayOf(1, 2, 3), start, end)
        "OK"
    } catch (failure: IndexOutOfBoundsException) {
        "IOOB"
    } catch (failure: IllegalArgumentException) {
        "IAE"
    }
}

fun main() {
    println("start-only:" + ByteString(byteArrayOf(1, 2, 3), startIndex = 1).toHexString())
    println("end-only:" + ByteString(bytesOnce(), endIndex = 2).toHexString() + ":" + evaluations)
    println("end-default:" + ByteString(bytesOnce(), startIndex = 1).toHexString() + ":" + evaluations)
    println("constructor-neg:" + constructorResult(-1, 2))
    println("constructor-high:" + constructorResult(0, 4))
    println("constructor-reversed:" + constructorResult(2, 1))
    println("constructor-both-neg:" + constructorResult(-1, -2))
    println("constructor-both-high:" + constructorResult(4, 3))
    println("constructor-equal-high:" + constructorResult(4, 4))

    val array = byteArrayOf(1, 2)
    val wrapped = UnsafeByteStringOperations.wrapUnsafe(array)
    UnsafeByteStringOperations.withByteArrayUnsafe(wrapped) {
        println("unsafe-read-only-identity:" + (it === array) + ":" + wrapped.toHexString())
    }
    var callbacks = 0
    try {
        UnsafeByteStringOperations.withByteArrayUnsafe(wrapped) {
            callbacks++
            throw IllegalStateException("callback")
        }
    } catch (failure: IllegalStateException) {
        println("unsafe-throw:" + callbacks)
    }
    println("unsafe-nlr:" + unsafeNonLocalReturn())

    val appendable = StringBuilder()
    val returned: StringBuilder = Base64.Default.encodeToAppendable(ByteString(0), appendable)
    println("appendable-identity:" + (returned === appendable) + ":" + returned)
    println("unsigned-factory:" + ByteString(128U.toUByte(), 255U.toUByte()).toHexString())
    println("order-less:" + (ByteString(1) < ByteString(2)))
    println("order-unsigned:" + (ByteString(255.toByte()) > ByteString(0)))

    val format = HexFormat { bytes { bytesPerLine = 1 } }
    try {
        println("hex-cr:" + "01\r02".hexToByteString(format).toHexString())
    } catch (failure: NumberFormatException) {
        println("hex-cr:NumberFormatException")
    }
    try {
        ByteString(0).toHexString(startIndex = -1)
        println("hex-range:OK")
    } catch (failure: IndexOutOfBoundsException) {
        println("hex-range:IOOB")
    }
}
