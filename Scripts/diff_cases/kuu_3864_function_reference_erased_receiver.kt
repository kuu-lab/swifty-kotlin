// KUU-3864: `Type::member` function references reflect the member in the
// *erased* receiver class parameterized by its own type parameters, matching
// JVM kotlin-reflect. Inherited generics substitute through the supertype
// instantiation (`A : H<A>` maps T to A) while the written LHS type
// arguments are ignored (`H<A>::foo` keeps `T`, `B<Int>::foo` keeps `U`).
interface H<T> {
    fun foo(x: T, y: Int): T?
    fun va(vararg ts: T): Int = ts.size
}
interface A : H<A>
interface B<U> : H<U>
class Impl : A {
    override fun foo(x: A, y: Int): A? = null
}
class C : H<C> {
    override fun foo(x: C, y: Int): C? = null
    fun member(m: C): Int = 1
}
fun top(x: Int, s: String): Boolean = s.length > x
fun String.ext(i: Int): Char = this[i % length]

fun main() {
    val a = Impl()
    val c = C()

    // Unbound references: return type and parameters substitute the declared
    // signature through the erased receiver class member scope.
    println(A::foo.returnType.toString())
    println(A::foo.parameters[0].type.toString())
    println(A::foo.parameters[1].type.toString())
    println(A::foo.parameters[2].type.toString())
    println(H<A>::foo.returnType.toString())
    println(H<A>::foo.parameters[0].type.toString())
    println(H<A>::foo.parameters[1].type.toString())
    println(B<Int>::foo.returnType.toString())
    println(B<Int>::foo.parameters[0].type.toString())
    println(B<Int>::foo.parameters[1].type.toString())

    // Bound references use the bound receiver's static type the same way.
    println(a::foo.returnType.toString())
    println(a::foo.parameters[0].type.toString())
    println(c::member.returnType.toString())
    println(C::member.parameters[0].type.toString())
    println(C::member.parameters[1].type.toString())

    // Vararg parameters reflect the declared element type wrapped in the
    // erased array form (`kotlin.Array<out U>`).
    println(A::va.parameters[1].type.toString())
    println(H<A>::va.parameters[1].type.toString())
    println(B<Int>::va.parameters[1].type.toString())
    println(A::va.parameters[1].isVararg.toString())

    // Non-member receivers keep their declared types (qualified primitives).
    println(::top.returnType.toString())
    println(::top.parameters[0].type.toString())
    println(::top.parameters[1].type.toString())
    println(String::ext.returnType.toString())
    println(String::ext.parameters[0].type.toString())
    println(String::ext.parameters[1].type.toString())
}
