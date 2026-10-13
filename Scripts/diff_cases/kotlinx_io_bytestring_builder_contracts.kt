import kotlinx.io.bytestring.*
import kotlinx.io.bytestring.append as appendBytes
import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

@OptIn(UnsafeByteStringApi::class)
fun main() {
    val builder = ByteStringBuilder()
    val bytes = byteArrayOf(1, 2, 3)
    builder.append(bytes, endIndex = 2)
    builder.append(bytes, startIndex = 2)
    builder.appendBytes(0x80u)
    builder.appendBytes(ByteString(4, 5))
    builder.appendBytes(6, 7)
    println(builder.toByteString().toHexString())
    println(buildByteString { append(bytes, endIndex = 1) }.toHexString())

    val full = ByteStringBuilder(2)
    full.append(byteArrayOf(1, 2))
    val first = full.toByteString()
    val second = full.toByteString()
    val left: ByteArray
    val right: ByteArray
    UnsafeByteStringOperations.withByteArrayUnsafe(first) { left = it }
    UnsafeByteStringOperations.withByteArrayUnsafe(second) { right = it }
    println("full-capacity-shares:" + (left === right))
    full.append(3)
    println("old-after-append:" + first.toHexString())
    println("new-after-append:" + full.toByteString().toHexString())

    var callbacks = 0
    UnsafeByteStringOperations.withByteArrayUnsafe(first) { callbacks++ }
    println("callbacks:" + callbacks)
}
