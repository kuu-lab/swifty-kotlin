import kotlinx.io.Buffer
import kotlinx.io.EOFException
import kotlinx.io.bytestring.ByteString
import kotlinx.io.readByteString
import kotlinx.io.snapshot
import kotlinx.io.write

fun main() {
    val buffer = Buffer()
    val bytes = ByteString(byteArrayOf(1, 2, 3))
    buffer.write(bytes)
    try { buffer.write(bytes, -1, 2) } catch (e: IndexOutOfBoundsException) { println("negative start") }
    try { buffer.write(bytes, 0, 4) } catch (e: IndexOutOfBoundsException) { println("large end") }
    try { buffer.write(bytes, 2, 1) } catch (e: IllegalArgumentException) { println("reversed range") }
    try { buffer.write(bytes, 4, 4) } catch (e: IndexOutOfBoundsException) { println("empty invalid range") }
    try { buffer.readByteString(-1) } catch (e: IllegalArgumentException) { println("negative count") }
    try { buffer.readByteString(4) } catch (e: EOFException) { println("EOF") }
    println(buffer.snapshot())
    println(buffer.size)
    buffer.clear()
    try { buffer.readByteString(1) } catch (e: EOFException) { println("empty EOF") }
    println(buffer.readByteString(0))
}
