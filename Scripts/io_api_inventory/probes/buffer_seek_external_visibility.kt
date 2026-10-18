import kotlinx.io.Buffer
import kotlinx.io.seek

fun main() {
    Buffer().seek(0L) { _, _ -> 0 }
}
