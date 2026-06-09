import kotlin.random.Random

fun useRandomDefault() {
    val rng = Random.Default
    val a = rng.nextInt()
    val b = rng.nextLong()
}
