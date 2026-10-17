import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.ByteStringBuilder
import kotlinx.io.bytestring.buildByteString

fun main() {
    val bytes = byteArrayOf(10, 20, 30, 40)

    val defaultBuilder = ByteStringBuilder()
    check(defaultBuilder.capacity == 0 && defaultBuilder.size == 0)
    println("constructor-default:${defaultBuilder.capacity}:${defaultBuilder.size}:${defaultBuilder.toByteString().size == 0}")
    println("constructor-explicit-zero:${ByteStringBuilder(0).capacity}")

    val appendAll = ByteStringBuilder()
    appendAll.append(bytes)
    check(appendAll.toByteString() == ByteString(10, 20, 30, 40))
    println("append-all:${appendAll.size}:${appendAll.toByteString() == ByteString(10, 20, 30, 40)}")

    val appendStart = ByteStringBuilder()
    appendStart.append(bytes, startIndex = 2)
    check(appendStart.toByteString() == ByteString(30, 40))
    println("append-start:${appendStart.size}:${appendStart.toByteString() == ByteString(30, 40)}")

    val appendEnd = ByteStringBuilder()
    appendEnd.append(bytes, endIndex = 2)
    check(appendEnd.toByteString() == ByteString(10, 20))
    println("append-end:${appendEnd.size}:${appendEnd.toByteString() == ByteString(10, 20)}")

    val appendExplicit = ByteStringBuilder()
    appendExplicit.append(bytes, 1, 3)
    check(appendExplicit.toByteString() == ByteString(20, 30))
    println("append-explicit:${appendExplicit.size}:${appendExplicit.toByteString() == ByteString(20, 30)}")

    var callbackCount = 0
    var callbackCapacity = -1
    val built = buildByteString {
        callbackCount++
        callbackCapacity = capacity
        append(bytes)
    }
    check(callbackCount == 1 && callbackCapacity == 0 && built == ByteString(10, 20, 30, 40))
    println("build-default:$callbackCount:$callbackCapacity:${built.size}:${built == ByteString(10, 20, 30, 40)}")

    try {
        ByteStringBuilder().append(bytes, startIndex = -1)
        println("append-default-negative-start:none")
    } catch (error: IndexOutOfBoundsException) {
        println("append-default-negative-start:IndexOutOfBoundsException")
    }

    try {
        ByteStringBuilder().append(bytes, endIndex = -1)
        println("append-default-negative-end:none")
    } catch (error: IllegalArgumentException) {
        println("append-default-negative-end:IllegalArgumentException")
    }
}
