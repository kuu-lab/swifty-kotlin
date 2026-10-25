import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.Base64

fun main() {
    val encoded = Base64.getEncoder().encodeToString(byteArrayOf(1))
    println(encoded)
    println(Base64.getDecoder().decode(encoded).joinToString(","))
    val urlEncoded = Base64.getUrlEncoder().withoutPadding().encodeToString(byteArrayOf(-1, 2))
    println(urlEncoded)
    println(Base64.getUrlDecoder().decode(urlEncoded).joinToString(","))
    val mimeEncoded = Base64.getMimeEncoder().encodeToString(ByteArray(60) { 1.toByte() })
    println(mimeEncoded.contains("\r\n"))
    println(Base64.getMimeDecoder().decode("A!Q==\n").joinToString(","))
    println(StandardCharsets.UTF_8.name())
    println(StandardCharsets.ISO_8859_1.name())
    println(Charset.forName("UTF-8").name())
    println(Charset.defaultCharset().name())
    println(Charset.availableCharsets().containsKey("UTF-8"))
    println(Charset.availableCharsets()["ISO-8859-1"]?.name())
}
