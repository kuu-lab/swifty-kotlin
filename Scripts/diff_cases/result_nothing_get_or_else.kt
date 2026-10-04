// KUU-564: A Nothing-valued runCatching result must infer the fallback type.
fun main() {
    println(runCatching { error("boom") }.getOrElse { -2 })
    println(runCatching { error("boom") }.onFailure { println("onf " + it.message) }.getOrElse { -4 })
}
