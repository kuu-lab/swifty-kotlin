import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

@OptIn(UnsafeByteStringApi::class)
@UnsafeByteStringApi
private class UnsafeBoundary

@OptIn(UnsafeByteStringApi::class)
fun main() {
    println(UnsafeByteStringOperations.wrapUnsafe(byteArrayOf(1, 2, 3)).size)
}
