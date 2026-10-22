import kotlin.random.Random
import kotlin.random.nextLong

fun useRandomNextLongRange() {
    val r = Random(42)
    val a = r.nextLong(10L..15L)
}
