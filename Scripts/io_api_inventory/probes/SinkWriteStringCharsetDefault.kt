import kotlinx.io.Buffer
import kotlinx.io.writeString
import kotlin.text.Charsets

fun main() {
    val charset = Charsets.UTF_32BE

    val bothDefaults = Buffer()
    bothDefaults.writeString(string = "", charset = charset)
    check(bothDefaults.size == 0L) { "both defaults did not preserve an empty buffer" }
    println("both-defaults=empty")

    val defaultStart = Buffer()
    defaultStart.writeString(string = "x", charset = charset, endIndex = 0)
    check(defaultStart.size == 0L) { "default startIndex did not preserve an empty range" }
    println("start-default=empty")

    val defaultEnd = Buffer()
    defaultEnd.writeString(string = "x", charset = charset, startIndex = 1)
    check(defaultEnd.size == 0L) { "default endIndex did not preserve an empty range" }
    println("end-default=empty")

    val explicitRange = Buffer()
    explicitRange.writeString(string = "x", charset = charset, startIndex = 1, endIndex = 1)
    check(explicitRange.size == 0L) { "explicit empty range did not preserve an empty buffer" }
    println("explicit-range=empty")
}
