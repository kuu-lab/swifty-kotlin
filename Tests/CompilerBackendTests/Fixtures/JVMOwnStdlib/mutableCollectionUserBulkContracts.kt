fun MutableList<Int>.removeAll(elements: Array<Int>): Boolean {
    println("custom remove")
    return false
}
fun MutableList<Int>.addAll(elements: Array<Int>): Boolean {
    println("custom add")
    return false
}
fun MutableSet<Int>.removeAll(elements: Array<Int>): Boolean {
    println("custom set remove")
    return false
}
fun MutableSet<Int>.addAll(elements: Array<Int>): Boolean {
    println("custom set add")
    return false
}
fun main() {
    val values = mutableListOf(1)
    println(values.removeAll(arrayOf(1)))
    println(values.addAll(arrayOf(2)))
    println(values)
    val set = mutableSetOf(1)
    println(set.removeAll(arrayOf(1)))
    println(set.addAll(arrayOf(2)))
    println(set)
}
