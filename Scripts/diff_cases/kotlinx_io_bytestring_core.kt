import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.ByteStringBuilder
import kotlinx.io.bytestring.buildByteString
import kotlinx.io.bytestring.decodeToString
import kotlinx.io.bytestring.encodeToByteString
import kotlinx.io.bytestring.indexOf
import kotlinx.io.bytestring.lastIndexOf
import kotlinx.io.bytestring.startsWith

fun main() {
    val original = byteArrayOf(65, 66, 65, 67)
    val value = ByteString(original)
    original[0] = 90
    println(value.toString())
    println(value.indexOf(65.toByte(), 1))
    println(value.lastIndexOf(65.toByte(), 1))
    println(value.startsWith(byteArrayOf(65, 66)))
    println(value.substring(1, 3).decodeToString())
    val copied = value.toByteArray()
    copied[0] = 90
    println(value[0])
    val builder = ByteStringBuilder(4)
    builder.append(value.toByteArray())
    val snapshot = builder.toByteString()
    builder.append(68.toByte())
    println(snapshot.toString())
    println("é".encodeToByteString().decodeToString())
    println(buildByteString { append(69.toByte()) }.decodeToString())
}
