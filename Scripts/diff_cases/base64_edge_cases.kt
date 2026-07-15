import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

@OptIn(ExperimentalEncodingApi::class)
fun main() {
    val bytes = "foo".encodeToByteArray()
    val encoded = Base64.Default.encode(bytes)
    println(encoded)
    println(Base64.Default.decode(encoded).decodeToString())
    println(Base64.UrlSafe.encode("\u083e".encodeToByteArray()))
    println(Base64.Mime.decode("Zm9v\r\nYmFy").decodeToString())
    println(Base64.Pem.decode("Zm9v\r\nYmFy").decodeToString())
    val encodedBytes = Base64.Default.encodeToByteArray(bytes)
    println(Base64.Default.encode(Base64.Default.decode(encodedBytes)))
    println(Base64.UrlSafe.encode(Base64.UrlSafe.decode(Base64.UrlSafe.encodeToByteArray("\u083e".encodeToByteArray()))))
    println(Base64.Default.encode(Base64.Mime.decode("Zm9v\r\nYmFy".encodeToByteArray())))
    val foob = "foob".encodeToByteArray()
    println(Base64.UrlSafe.encode(foob))
    val defaultNoPad = Base64.Default.withPadding(Base64.PaddingOption.ABSENT)
    println(defaultNoPad.encode(foob))
    println(Base64.Default.encode(defaultNoPad.decode("Zm9vYg")))
    val urlSafeNoPad = Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT_OPTIONAL)
    println(urlSafeNoPad.encode("\u083e!".encodeToByteArray()))
    println(Base64.Default.encode(urlSafeNoPad.decode("4KC-IQ==")))
    val mimeNoPad = Base64.Mime.withPadding(Base64.PaddingOption.ABSENT)
    println(mimeNoPad.encode(foob))

    // Mime wraps at 76 chars (RFC 2045), Pem at 64 (RFC 1421) -- distinct
    // line lengths despite sharing the standard alphabet.
    val longBytes = ByteArray(60) { 0x41 }
    for (line in Base64.Mime.encode(longBytes).split("\r\n")) {
        println(line.length)
    }
    for (line in Base64.Pem.encode(longBytes).split("\r\n")) {
        println(line.length)
    }
}
