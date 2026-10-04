class A {
    var total: Int = 0
        get() = field + 100
}

fun main() {
    val a = A()
    a.total += 1
    println(a.total)
}
