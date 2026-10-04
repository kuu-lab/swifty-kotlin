import kotlinx.io.Buffer
import kotlinx.io.Source
import kotlinx.io.bytestring.ByteString
import kotlinx.io.indexOf
import kotlinx.io.write

fun main() {
    val buffer = Buffer()
    buffer.write(ByteString(byteArrayOf(1, 2, 1, 2, 1, 3)))
    val pattern = ByteString(byteArrayOf(1, 2, 1))
    println(buffer.indexOf(pattern))
    println(buffer.indexOf(pattern, 1))
    println(buffer.indexOf(pattern, -5))
    println(buffer.indexOf(pattern, 4))
    println(buffer.indexOf(ByteString(byteArrayOf(3))))
    println(buffer.indexOf(ByteString(byteArrayOf(4))))
    println(buffer.indexOf(ByteString(), -1))
    println(buffer.indexOf(ByteString(), 3))
    println(buffer.indexOf(ByteString(), 100))
    println(buffer.indexOf(pattern, 100))
    println(buffer.indexOf(ByteString(byteArrayOf(1, 2, 1, 2, 1, 3, 4))))
    val source: Source = buffer
    println(source.indexOf(pattern, 1))
    println(source.indexOf(ByteString(), 100))
    println(buffer.size)
    println(Buffer().indexOf(ByteString()))
    println(Buffer().indexOf(pattern))

    val data = ByteArray(17000)
    data[8190] = 9
    data[8191] = 8
    data[8192] = 7
    data[16383] = 9
    data[16384] = 8
    data[16385] = 7
    val segmented = Buffer()
    segmented.write(ByteString(data))
    val crossing = ByteString(byteArrayOf(9, 8, 7))
    println(segmented.indexOf(crossing))
    println(segmented.indexOf(crossing, 8191))
    println(segmented.indexOf(crossing, 16384))
    // The first matching byte is after the outbound scan's initial offset.
    val lastByte = ByteString(byteArrayOf(8, 7))
    println(segmented.indexOf(lastByte))
    println(segmented.indexOf(lastByte, 8192))
    segmented.skip(8189)
    println(segmented.indexOf(crossing))
    println(segmented.size)

    val longPattern = ByteArray(9000)
    longPattern[0] = 11
    longPattern[8999] = 12
    val multiSegment = Buffer()
    multiSegment.write(ByteArray(8000))
    multiSegment.write(ByteString(longPattern))
    println(multiSegment.indexOf(ByteString(longPattern)))
    println(multiSegment.indexOf(ByteString(longPattern), 8001))
}
