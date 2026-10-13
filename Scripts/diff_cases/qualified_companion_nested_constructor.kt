// KUU-1952: qualified calls must consider companion functions and nested constructors together.
class A { companion object { fun B(x: Int) = 42 }; class B(val xs: List<String>) }

class Named {
    companion object Factory {
        private val marker = 43
        fun B(x: Int): Int = marker
    }
    class B(val value: String)
}

enum class Direction { NORTH }

class Generic {
    companion object {
        inline fun <reified T : Enum<T>> Choice(): String = "generic factory"
    }
    class Choice<T : Any>(val choices: List<T>)
}

class ConstructorPriority {
    companion object { fun B(value: Int): String = "specific factory" }
    class B(val value: Number)
}

class SameShape {
    companion object { fun B(value: Int): String = "same-shaped factory" }
    class B(val value: Int)
}

class LiteralConstructor {
    companion object { fun B(value: Int): String = "literal factory" }
    class B(val value: Long)
}

class NarrowLiteralConstructor {
    companion object { fun B(value: Int): String = "narrow literal factory" }
    class B(val value: Byte)
}

class GenericFactory {
    companion object { fun <T> B(): Int = 44 }
    class B
}

class ExtensionOwner { companion object; class B(val value: String) }
fun ExtensionOwner.Companion.B(value: Int): Int = 45

fun main() {
    println(A.B(5))
    println(A.B(listOf("constructor")).xs[0])
    println(Named.B(5))
    println(Named.B("named constructor").value)
    println(Generic.Choice<Direction>())
    println(Generic.Choice<Int>(listOf(7)).choices[0])
    println(ConstructorPriority.B(1).value)
    println(SameShape.B(9).value)
    println(LiteralConstructor.B(11).value)
    println(NarrowLiteralConstructor.B(12).value)
    println(GenericFactory.B<Int>())
    println(ExtensionOwner.B(5))
}
