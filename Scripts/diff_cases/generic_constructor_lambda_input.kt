// KUU-2141: infer the invariant carrier from an explicitly typed callback input.
class Holder<T>(val action: (T) -> Unit)

class Host {
    fun <T> accept(value: T, holder: Holder<T>) {
        holder.action(value)
    }
}

fun requiresString(holder: Holder<String>) {
    holder.action("fixed")
}

fun main() {
    Host().accept("nested", Holder { value: String -> println(value) })
    val suffix = "!"
    val holder = Holder { value: String -> println(value + suffix) }
    Host().accept("preconstructed", holder)
    requiresString(holder)
    Host().accept<String>("explicit-member", Holder { value: String -> println(value) })
    val typed: Holder<String> = Holder { value: String -> println(value) }
    Host().accept("typed-local", typed)
    val explicit = Holder<String> { value: String -> println(value) }
    requiresString(explicit)
    val discarding = Holder { value: String -> value.length }
    requiresString(discarding)
    println("unit-coercion")
    val offset = 12
    Host().accept(7, Holder { value: Int -> println(value + offset) })
}
