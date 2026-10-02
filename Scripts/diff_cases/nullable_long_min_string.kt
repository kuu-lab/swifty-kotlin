package diff

fun main() {
    val minimum: Long? = Long.MIN_VALUE
    val absent: Long? = null
    val ordinary: Long? = 42L

    println(minimum)
    println("$minimum")
    println("value=" + minimum)
    println(minimum == Long.MIN_VALUE)
    println(absent)
    println("$absent")
    println("$ordinary")
}
