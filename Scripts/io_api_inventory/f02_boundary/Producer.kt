package f02boundary

import kotlinx.io.*
import kotlinx.io.bytestring.*
import java.io.InputStream

private var initialization = ""
private fun initialize(label: String): Buffer {
    initialization += label
    return Buffer().apply { writeString(label) }
}
private val first = initialize("A")
private val second = initialize("B")

public val initializationOrder: String get() = initialization
public val initialBytes: ByteString get() = first.snapshot()

public inline fun inspect(value: ByteString = initialBytes, callback: (ByteString) -> Unit) {
    callback(value)
}

public fun retainedCallback(): () -> String {
    val buffer = Buffer().apply { writeString("captured") }
    return { buffer.readString() }
}

public fun retainedInput(): InputStream = second.asInputStream()

public fun producerMain() {
    println("ordinary-producer-function:" + initializationOrder)
}
