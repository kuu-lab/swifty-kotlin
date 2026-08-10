fun main() {
    val v = KotlinVersion(1, 9, 24)
    println(v.major)
    println(v.minor)
    println(v.patch)
    println(v.toString())
    println(v.isAtLeast(1, 9))
    println(v.isAtLeast(1, 9, 24))
    println(v.isAtLeast(1, 9, 25))
    println(v.isAtLeast(2, 0))

    val short = KotlinVersion(2, 1)
    println(short)
    println(short > v)
    println(short.compareTo(v) > 0)
    println(short == KotlinVersion(2, 1, 0))
    println(KotlinVersion.MAX_COMPONENT_VALUE)
}
