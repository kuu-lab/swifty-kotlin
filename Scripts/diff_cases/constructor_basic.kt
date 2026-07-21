// Constructor delegation must run the primary initializer for both constructors.
class Counter(start: Int) {
    init {
        println("Counter($start)")
    }

    constructor() : this(0)
}

fun main() {
    Counter(1)
    Counter()
}
