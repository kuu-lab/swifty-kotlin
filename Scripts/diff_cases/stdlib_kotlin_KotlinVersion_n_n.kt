fun main() {
    val short = KotlinVersion(2, 1)
    val full = KotlinVersion(2, 1, 20)

    println(short.toString())
    println(full.toString())
    println(KotlinVersion.MAX_COMPONENT_VALUE)
}
