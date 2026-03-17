import kotlin.random.Random

fun main() {
    val r1 = Random(42)
    val r2 = Random(42)
    println(r1.nextInt(100))
    println(r2.nextInt(100))
    println(r1.nextInt(100) == r2.nextInt(100))
    val r3 = Random(0)
    println(r3.nextInt(100))
    println(r3.nextBoolean())
}
