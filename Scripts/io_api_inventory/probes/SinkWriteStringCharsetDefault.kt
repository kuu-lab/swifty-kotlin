import kotlinx.io.Buffer
import kotlinx.io.bytestring.toHexString
import kotlinx.io.snapshot
import kotlinx.io.writeString
import kotlin.text.Charsets

fun main() {
    val text = "təˈranəˌsôr"
    val charset = Charsets.UTF_32BE

    val full = Buffer()
    full.writeString(string = text, charset = charset)
    println("both-defaults:" + full.snapshot().toHexString())

    val defaultStart = Buffer()
    defaultStart.writeString(string = text, charset = charset, endIndex = 7)
    println("start-default:" + defaultStart.snapshot().toHexString())

    val defaultEnd = Buffer()
    defaultEnd.writeString(string = text, charset = charset, startIndex = 3)
    println("end-default:" + defaultEnd.snapshot().toHexString())

    val explicitRange = Buffer()
    explicitRange.writeString(string = text, charset = charset, startIndex = 3, endIndex = 7)
    println("explicit-range:" + explicitRange.snapshot().toHexString())
}
