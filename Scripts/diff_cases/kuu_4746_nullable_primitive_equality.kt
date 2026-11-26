// DIFF_WASM
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

fun main() {
    val missingLong: Long? = null
    val presentLong: Long? = 42L
    println(missingLong == null)
    println(missingLong != null)
    println(presentLong == null)
    println(presentLong != null)

    val missingDuration: Duration? = null
    val presentDuration: Duration? = 1.seconds
    println(missingDuration == null)
    println(missingDuration != null)
    println(presentDuration == null)
    println(presentDuration != null)
    println(Duration.parseOrNull("not-a-duration") == null)
}
