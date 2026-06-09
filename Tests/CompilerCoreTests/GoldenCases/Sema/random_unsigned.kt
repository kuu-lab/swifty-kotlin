import kotlin.random.Random

fun useRandomUnsigned() {
    val a = Random.nextUInt()
    val b = Random.nextUInt(10u)
    val c = Random.nextUInt(1u, 10u)
    val d = Random.nextULong()
    val e = Random.nextULong(100uL)
    val f = Random.nextULong(10uL, 100uL)
}
