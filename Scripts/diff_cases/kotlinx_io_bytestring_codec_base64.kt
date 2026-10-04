import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.decode
import kotlinx.io.bytestring.decodeIntoByteArray
import kotlinx.io.bytestring.decodeToByteString
import kotlinx.io.bytestring.decodeToString
import kotlinx.io.bytestring.encode
import kotlinx.io.bytestring.encodeIntoByteArray
import kotlinx.io.bytestring.encodeToAppendable
import kotlinx.io.bytestring.encodeToByteArray
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

@OptIn(ExperimentalEncodingApi::class)
fun main() {
    val value = ByteString("Hello".encodeToByteArray())
    println(Base64.encode(value))
    println(Base64.encodeToByteArray(value).decodeToString())

    val dest = ByteArray(16)
    val written = Base64.encodeIntoByteArray(value, dest, 0)
    println("$written:${dest.decodeToString(0, written)}")

    val sb = StringBuilder()
    Base64.encodeToAppendable(value, sb)
    println(sb.toString())

    val encoded = ByteString("SGVsbG8=".encodeToByteArray())
    println(Base64.decode(encoded).decodeToString())
    println(Base64.decodeToByteString("SGVsbG8=").decodeToString())
    println(Base64.decodeToByteString(encoded).decodeToString())
    try {
        Base64.decodeToByteString("SGVsbG8".encodeToByteArray())
    } catch (e: IllegalArgumentException) {
        println("decodeToByteString-missing-padding")
    }
    val optional = Base64.Default.withPadding(Base64.PaddingOption.PRESENT_OPTIONAL)
    println(optional.decodeToByteString("SGVsbG8").decodeToString())

    val out = ByteArray(8)
    val count = Base64.decodeIntoByteArray(encoded, out, 0)
    println("$count:${out.decodeToString(0, count)}")

    val urlSafe = ByteString(byteArrayOf(62, 62, 62))
    println(Base64.UrlSafe.encode(urlSafe))
    println(Base64.UrlSafe.decodeToByteString("Pj4-").decodeToString())

    // Same-named Base64 member calls must keep resolving while the
    // ByteString extensions are imported (member takes precedence when
    // its signature applies).
    println(Base64.encode("Hi".encodeToByteArray()))
    println(Base64.decode("SGk=").decodeToString())
    println(Base64.encodeToByteArray("Hi".encodeToByteArray()).decodeToString())
}
