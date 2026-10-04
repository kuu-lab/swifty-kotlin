package golden.sema

class CovariantBox<out T> {
    fun accept(value: @UnsafeVariance T): T = value
}

fun useUnsafeVariance(box: CovariantBox<String>): String = box.accept("accepted")
