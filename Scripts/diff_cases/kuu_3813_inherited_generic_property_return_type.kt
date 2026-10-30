// KUU-3813: `Type::member` reflects the member in the erased receiver class
// parameterized by its own type parameters — inherited generics are
// substituted through the supertype instantiation (A : H<A> → T=A), while
// written LHS type arguments are ignored (H<A>::parent stays T?).
// A bound `expr::member` substitutes through the bound receiver's static type.
interface H<T> { val parent: T? }
interface A : H<A>
interface B<U> : H<U>
interface C : A
class Impl : A { override val parent: A? get() = null }

fun main() {
    println(A::parent.returnType.toString())
    println(B<Int>::parent.returnType.toString())
    println(C::parent.returnType.toString())
    println(H<A>::parent.returnType.toString())
    println(A::parent.parameters[0].type.toString())
    println(H<A>::parent.parameters[0].type.toString())
    val a: A = Impl()
    println(a::parent.returnType.toString())
}
