import kotlin.random.Random
import kotlin.random.nextInt

fun useRandomNextIntRange() {
    val r = Random(42)
    val a = r.nextInt(10..15)
}
