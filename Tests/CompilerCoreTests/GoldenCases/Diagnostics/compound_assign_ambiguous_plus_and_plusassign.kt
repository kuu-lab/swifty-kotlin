class Counter(var value: Int) {
    operator fun plus(other: Counter): Counter = Counter(value + other.value)
    operator fun plusAssign(other: Counter) {
        value += other.value
    }
}

fun main() {
    var c = Counter(1)
    c += Counter(2)
}
