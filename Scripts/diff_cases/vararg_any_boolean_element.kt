fun printAll(vararg items: Any) {
    items.forEach { println(it) }
}
fun main() {
    printAll("Hello", 42, true)
}
