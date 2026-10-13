var trace = ""

fun main() {
    println(iterator<Int> {
        trace += "before;"
        yield(1)
        trace += "after;"
        yield(2)
    }.asSequence().toList())
    println(trace)
}
