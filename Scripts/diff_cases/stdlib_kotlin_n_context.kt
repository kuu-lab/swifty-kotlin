import kotlin.ExperimentalContextParameters

class ContextTag(val label: String)

@OptIn(ExperimentalContextParameters::class)
fun main() {
    println(context("one") { contextOf<String>() })
    println(context(1, 2, 3, 4, 5, ContextTag("six")) { contextOf<ContextTag>().label })
}
