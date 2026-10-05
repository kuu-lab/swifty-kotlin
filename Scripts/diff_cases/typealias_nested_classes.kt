package nestedalias

typealias Alias = Outer.Nested
typealias GenericAlias<T> = Outer.Box<T>
typealias NullableAlias = Outer.Nested?
typealias DeepAlias = Outer.Middle.Deep
typealias CompanionAlias = Outer.Companion.Nested
typealias NamedCompanionAlias = FactoryOwner.Factory.Nested
typealias ObjectAlias = ObjectOwner.Nested
typealias InterfaceAlias = InterfaceOwner.Nested
typealias EnumAlias = EnumOwner.Nested

class Outer {
    class Nested { fun f() = "n" }
    class Box<T>(val value: T)
    class Middle { class Deep { fun f() = "deep" } }
    companion object { class Nested { fun f() = "companion" } }
}

class FactoryOwner {
    companion object Factory { class Nested { fun f() = "named" } }
}
object ObjectOwner { class Nested { fun f() = "object" } }
interface InterfaceOwner { class Nested { fun f() = "interface" } }
enum class EnumOwner { ONLY; class Nested { fun f() = "enum" } }

fun throughAlias(value: Alias): String = value.f()

fun main() {
    println(Alias().f())
    println(throughAlias(Alias()))
    val box: GenericAlias<String> = GenericAlias("generic")
    println(box.value)
    val nullable: NullableAlias = Alias()
    println(nullable?.f())
    val absent: NullableAlias = null
    println(absent?.f())
    println(DeepAlias().f())
    println(CompanionAlias().f())
    println(NamedCompanionAlias().f())
    println(ObjectAlias().f())
    println(InterfaceAlias().f())
    println(EnumAlias().f())
    println(Outer.Nested().f())
}
