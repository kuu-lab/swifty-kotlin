@file:OptIn(kotlin.ExperimentalStdlibApi::class)

fun main() {
    useExperimentalStdlibApi()
}

@kotlin.ExperimentalStdlibApi
fun useExperimentalStdlibApi() {
    println("OK")
}
