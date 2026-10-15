// Regression coverage for enum-entry-owned properties accessed from overrides.
// The first enum mirrors Kotlin's kt1119.kt; the second mirrors kt9711.kt.
enum class Direction() {
    NORTH {
        val someSpecialValue = "OK"
        override fun f() = someSpecialValue
    },
    SOUTH { override fun f() = "LITERAL" };
    val bodyValue = "CLASS"
    fun readBodyValue() = bodyValue
    abstract fun f(): String
}

enum class X {
    B {
        val value2 = "OK"
        override val value = { value2 }
    };
    abstract val value: () -> String
}

fun main() {
    println(Direction.NORTH.f())
    println(Direction.SOUTH.f())
    println(Direction.NORTH.readBodyValue())
    println(X.B.value())
}
