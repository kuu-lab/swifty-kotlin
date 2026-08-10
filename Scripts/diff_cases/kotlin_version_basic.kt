fun main() {
    val short = KotlinVersion(2, 1)
    val full = KotlinVersion(2, 1, 20)

    println(short)
    println(full)
    println(short.major)
    println(short.minor)
    println(short.patch)
    println(full.patch)
    println(KotlinVersion.MAX_COMPONENT_VALUE)

    // The concrete value of CURRENT tracks the compiler's own version, so only
    // version-independent facts about it are comparable against kotlinc.
    println(KotlinVersion.CURRENT.isAtLeast(1, 0))
    println(KotlinVersion.CURRENT > KotlinVersion(1, 0, 0))

    println(full.compareTo(short) > 0)
    println(short.compareTo(full) < 0)
    println(short < full)
    println(full >= KotlinVersion(2, 1, 20))
    println(full.isAtLeast(2, 1))
    println(full.isAtLeast(2, 2))
    println(full.isAtLeast(2, 1, 20))
    println(full.isAtLeast(2, 1, 21))
    println(full == KotlinVersion(2, 1, 20))
    println(full == short)
    println(full.hashCode() == KotlinVersion(2, 1, 20).hashCode())
}
