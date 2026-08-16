@SinceKotlin("1.4")
class SinceKotlinHost {
    @SinceKotlin("1.5")
    val value: Int = 1

    @SinceKotlin("1.6")
    fun expose(): Int = value
}

@SinceKotlin("1.7")
typealias SinceKotlinHostAlias = SinceKotlinHost

fun main() {
    val host = SinceKotlinHost()
    val alias: SinceKotlinHostAlias = host
    println(alias.expose())
}
