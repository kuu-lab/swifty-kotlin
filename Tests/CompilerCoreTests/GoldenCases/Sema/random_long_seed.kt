import kotlin.random.Random

fun useRandomLongSeed() {
    val r = Random(42L)
    val a = r.nextInt()
    val b = r.nextLong()
}
