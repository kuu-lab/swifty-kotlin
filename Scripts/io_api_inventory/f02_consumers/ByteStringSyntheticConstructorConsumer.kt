package f02constructorconsumer

import f02constructorproducer.constructorWithAllDefaults
import f02constructorproducer.constructorWithDefaultEnd
import kotlinx.io.bytestring.ByteString

private fun bytes(value: ByteString): String = value.toByteArray().joinToString(",")

private fun expectException(expected: String, body: () -> Unit): String {
    try {
        body()
    } catch (failure: Throwable) {
        val actual = failure::class.simpleName ?: failure::class.toString()
        check(actual == expected) { "expected $expected, got $actual" }
        return actual
    }
    error("expected $expected")
}

private fun expectIndexOutOfBounds(body: () -> Unit): String {
    try {
        body()
    } catch (_: IndexOutOfBoundsException) {
        return "IndexOutOfBoundsException"
    }
    error("expected IndexOutOfBoundsException")
}

fun main() {
    val input = byteArrayOf(0, 1, 2, 3)
    val withAllDefaults = ByteString(input)
    val withDefaultEnd = ByteString(input, 1)
    val explicitRange = ByteString(input, 1, 3)
    val emptyRange = ByteString(input, 2, 2)

    check(bytes(withAllDefaults) == "0,1,2,3")
    check(bytes(withDefaultEnd) == "1,2,3")
    check(bytes(explicitRange) == "1,2")
    check(emptyRange.size == 0)

    val producerDefaults = constructorWithAllDefaults(input)
    val producerDefaultEnd = constructorWithDefaultEnd(input)
    check(bytes(producerDefaults) == "0,1,2,3")
    check(bytes(producerDefaultEnd) == "1,2,3")

    input[0] = 99
    val returnedArray = withAllDefaults.toByteArray()
    returnedArray[0] = 98
    check(bytes(withAllDefaults) == "0,1,2,3")

    val exceptions = listOf(
        expectIndexOutOfBounds { ByteString(input, -1, 1) },
        expectException("IllegalArgumentException") { ByteString(input, 2, 1) },
        expectIndexOutOfBounds { ByteString(input, 0, input.size + 1) },
    )

    println("defaults=${bytes(withAllDefaults)};${bytes(withDefaultEnd)};${bytes(explicitRange)}")
    println("producer-defaults=${bytes(producerDefaults)};${bytes(producerDefaultEnd)}")
    println("copy-isolated=${bytes(withAllDefaults)}")
    println("exceptions=${exceptions.joinToString(",")}")
}
