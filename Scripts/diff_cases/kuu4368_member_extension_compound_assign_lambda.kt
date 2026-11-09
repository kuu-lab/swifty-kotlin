// KUU-4368: `sum += x` on a generic `var sum: T` inside a lambda nested in
// `with(field)` must resolve the member-extension `operator fun T.plus`
// supplied by the implicit dispatch receiver (fixed by KUU-4420).
interface Field<T> {
    val zero: T
    operator fun T.plus(other: T): T
}

class IntField : Field<Int> {
    override val zero: Int = 0
    override fun Int.plus(other: Int): Int = this + other
}

class G<T>(val field: Field<T>) {
    fun compute(data: List<T>): Pair<T, Int> = with(field) {
        var sum = zero
        data.indices.forEach { sum += data[it] }
        sum to data.size
    }
}

fun main() {
    val (sum, n) = G(IntField()).compute(listOf(1, 2, 3))
    println(sum)
    println(n)
}
