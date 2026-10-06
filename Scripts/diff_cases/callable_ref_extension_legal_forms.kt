// KUU-961: the `::` forms kotlinc accepts for extension declarations must
// keep working — bare `::ext` rejection is covered by Sema unit tests
// (diff cases require both compilers to succeed).
fun Int.even(): Boolean = this % 2 == 0
val Int.lastDigit: Int get() = this % 10
fun String.tag(): String = "ext:" + this

fun main() {
    // Type::ext — unbound extension function reference
    val unbound: (Int) -> Boolean = Int::even
    println(unbound(6))

    // obj::ext — bound extension function reference
    val bound: () -> Boolean = 6::even
    println(bound())

    // Implicitly-bound extension reference inside a receiver scope:
    // `with(4) { ::even }` means `4::even`, typed `() -> Boolean`.
    val viaScope: () -> Boolean = with(4) { ::even }
    println(viaScope())

    // Extension property references via `Type::` and `obj::`
    println(Int::lastDigit.get(37))
    println(37::lastDigit.get())

    // Bound extension through a scope function receiver
    println("hi".run { ::tag }())

    // Bare `::name` to a non-extension stays legal
    fun double(x: Int): Int = x * 2
    println((::double)(21))
}
