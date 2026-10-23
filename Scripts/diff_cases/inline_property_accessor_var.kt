var backing = 1

private inline var value: Int
    get() = backing + 10000
    set(v) { backing = v + 100 }

fun main() {
    value = 5
    println(value)
}
