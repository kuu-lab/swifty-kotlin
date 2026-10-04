import kotlin.ExperimentalContextParameters

class Tag(val label: String)

@OptIn(ExperimentalContextParameters::class)
fun main() {
    println(context(42) { contextOf<Int>() })
    println(context("a", 3) { contextOf<String>().repeat(contextOf<Int>()) })
    println(context(1, "b", true, 4L, 'y', Tag("t")) { contextOf<Tag>().label + contextOf<Char>() })

    val nested = context(10) {
        val outer = contextOf<Int>()
        context("inner") { contextOf<String>().length + outer }
    }
    println(nested)
}
