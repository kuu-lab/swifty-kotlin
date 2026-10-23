// KUU-2935: a companion object's `toString()` override was ignored when the
// companion crossed an `Any` boundary -- `<object 0x...>` was printed instead
// of the override's result, because the eager `__companion_init_*` path never
// emitted `kk_object_register_any_to_string`.
// JetBrains: objects/companionObjectAccess/privateCompanionObjectUsedInNestedClass.kt
class Outer {
    private companion object {
        override fun toString(): String = "OK"
    }
    class Nested { fun foo(): Any = Outer.Companion }
    fun test() = Nested().foo().toString()
}

class Named {
    companion object Factory {
        override fun toString(): String = "Factory"
    }
}

fun main() {
    println(Outer().test())
    val erased: Any = Named.Factory
    println(erased)
    println(erased.toString())
    println("$erased")
}
