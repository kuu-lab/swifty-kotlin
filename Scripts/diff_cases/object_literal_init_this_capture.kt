// KUU-4606 follow-up: an object literal created in a class initializer must
// capture the instance under construction for `this@Outer`, not leave the
// capture field zeroed. kotlinc prints "ok".
class Outer(val tag: String) {
    interface Reader {
        fun outer(): Outer
    }

    val reader: Reader

    init {
        reader = object : Reader {
            override fun outer(): Outer = this@Outer
        }
    }
}

fun main() {
    println(Outer("ok").reader.outer().tag)
}
