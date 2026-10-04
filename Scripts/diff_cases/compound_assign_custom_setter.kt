class A {
    var total: Int = 0
        set(v) {
            println("set $v")
            field = v * 2
        }
}

fun main() {
    val a = A()
    a.total += 1
    println(a.total)
    a.total++
    println(a.total)
}
