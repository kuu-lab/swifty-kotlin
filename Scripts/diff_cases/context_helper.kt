import kotlin.ExperimentalContextParameters

class Tag(val label: String)

@OptIn(ExperimentalContextParameters::class)
fun main() {
    println(context(1) { "one" })
    println(context(1, "b") { 3 })
    println(context(1, "b", true) { "three" })
    println(context(1, "b", true, 4L) { 'x' })
    println(context(1, "b", true, 4L, 'y') { 6 })
    println(context(1, "b", true, 4L, 'y', Tag("t")) { "six" })

    val computed = context(10) {
        val doubled = 2 * 10
        doubled + 1
    }
    println(computed)

    var counter = 0
    context(Tag("outer")) {
        counter += 1
    }
    println(counter)
}
