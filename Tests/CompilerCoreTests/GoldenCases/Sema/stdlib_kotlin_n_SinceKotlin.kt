package golden.sema

@SinceKotlin("1.4")
class SinceKotlinHost {
    @SinceKotlin("1.5")
    val value: Int = 1

    @SinceKotlin("1.6")
    fun expose(): Int = value
}

@SinceKotlin("1.7")
typealias SinceKotlinHostAlias = SinceKotlinHost

@SinceKotlin("1.8")
fun useSinceKotlinHost(host: SinceKotlinHost): Int = host.expose()

fun createSinceKotlinHost(): SinceKotlinHostAlias = SinceKotlinHost()
