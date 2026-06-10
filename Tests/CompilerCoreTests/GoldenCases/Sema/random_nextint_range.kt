import kotlin.random.Random

fun useRandomNextIntRange() {
    val r = Random(42)
    val a = r.nextInt(10..15)
}
