// BUG-243: An object-literal member function must capture an immutable
// property declared by the enclosing class's primary constructor.
interface Probe {
    fun value(): Int
}

class Counter(private val limit: Int) {
    fun probe(): Probe {
        return object : Probe {
            override fun value(): Int {
                return limit
            }
        }
    }
}

fun main() {
    println(Counter(3).probe().value())
}
