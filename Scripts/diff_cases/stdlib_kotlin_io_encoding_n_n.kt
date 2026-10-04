import kotlin.io.encoding.ExperimentalEncodingApi

@ExperimentalEncodingApi
fun experimentalEncodingApiSurface(): String = "ok"

@OptIn(ExperimentalEncodingApi::class)
fun main() {
    println(experimentalEncodingApiSurface())
}
