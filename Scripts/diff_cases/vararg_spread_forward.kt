fun sink(vararg xs: String): String = xs.joinToString(",") + "#" + xs.size
fun sinkI(vararg xs: Int): String = xs.joinToString(",") + "#" + xs.size
fun mid(vararg parts: String): String = sink("h", *parts, "t")
fun mid2(vararg parts: String): String = sink(*parts)
fun midI(vararg parts: Int): String = sinkI(0, *parts, 9)
fun midI2(vararg parts: Int): String = sinkI(*parts)
fun main() {
    println(mid("a", "b"))
    println(mid())
    println(mid2("a", "b"))
    println(midI(1, 2))
    println(midI2(1, 2))
}
