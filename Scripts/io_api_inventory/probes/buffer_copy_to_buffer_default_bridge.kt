import kotlinx.io.Buffer

fun main() {
    val wholeSource = Buffer()
    val wholeTarget = Buffer()
    wholeSource.copyTo(wholeTarget)
    if (wholeSource.size != 0L || wholeTarget.size != 0L) {
        throw IllegalStateException("empty full-range copy changed buffer size")
    }

    val omittedStartSource = Buffer()
    val omittedStartTarget = Buffer()
    omittedStartSource.copyTo(omittedStartTarget, endIndex = 0L)
    if (omittedStartSource.size != 0L || omittedStartTarget.size != 0L) {
        throw IllegalStateException("empty copy with omitted start changed buffer size")
    }

    val omittedEndSource = Buffer()
    val omittedEndTarget = Buffer()
    omittedEndSource.copyTo(omittedEndTarget, startIndex = 0L)
    if (omittedEndSource.size != 0L || omittedEndTarget.size != 0L) {
        throw IllegalStateException("empty copy with omitted end changed buffer size")
    }

    println("PASS: Buffer.copyTo(Buffer) default range dispatch")
}
