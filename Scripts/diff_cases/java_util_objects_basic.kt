// KUU-3056: the bundled facade should expose java.util.Objects' core helpers.
// KOTLINC_FLAGS: -Xjdk-release=17
import java.util.Objects

private class Value(val number: Int) {
    override fun equals(other: Any?): Boolean = other is Value && number == other.number
    override fun hashCode(): Int = number * 10
    override fun toString(): String = "value:$number"
}

fun main() {
    println(Objects.equals(1, 1))
    println(Objects.equals(1, 1L))
    println(Objects.equals(null, null))
    println(Objects.equals(null, 1))
    println(Objects.equals(Value(2), Value(2)))

    println(Objects.hash(1, 2))
    println(Objects.hash())
    println(Objects.hash(null))
    println(Objects.hash(Value(2)))

    println(Objects.toString(1))
    println(Objects.toString(null))
    println(Objects.toString(null, "fallback"))
    println(Objects.toString(1, "fallback"))
    println(Objects.toString(Value(2)))

    println(Objects.requireNonNull(1))
    try {
        Objects.requireNonNull(null as String?)
        println("not thrown")
    } catch (failure: NullPointerException) {
        println("requireNonNull:null")
    }
    try {
        Objects.requireNonNull(null as String?, "missing")
        println("not thrown")
    } catch (failure: NullPointerException) {
        println(failure.message)
    }

    println(Objects.isNull(null))
    println(Objects.isNull(1))
    println(Objects.nonNull(null))
    println(Objects.nonNull(1))

    println(Objects.hashCode(null))
    println(Objects.hashCode(1))
    println(Objects.hashCode(Value(2)))
}
