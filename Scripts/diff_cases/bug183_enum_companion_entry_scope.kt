// BUG-183 minimal repro: enum entries must be visible without qualification
// inside the enum's companion object.

enum class D {
    A, B;
    companion object {
        fun pick(o: Int): D = if (o == 0) A else B
    }
}

fun main() {
    println(D.pick(0))
    println(D.pick(1))
}
