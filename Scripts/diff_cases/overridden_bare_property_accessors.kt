// KUU-3607: default accessors on overridden stored properties must dispatch
// through the generic superclass slot and access the subclass's own field.
open class Base<T> {
    open var x: T = "base" as T
        get
}

class Derived : Base<String>() {
    override var x: String = "child"
        set
}

open class ReverseBase<T> {
    open var x: T = "base" as T
        set
}

class ReverseDerived : ReverseBase<String>() {
    override var x: String = "reverse"
        get
}

open class PlainBase<T> {
    open var x: T = "base" as T
}

class PlainDerived : PlainBase<String>() {
    override var x: String = "plain"
}

class CustomDerived : PlainBase<String>() {
    override var x: String = "custom"
        set(value) { field = "custom:" + value }
}

open class ValueBase<T>(initial: T) {
    open var x: T = initial
}

class IntDerived : ValueBase<Int>(1) {
    override var x: Int = 2
}

class DoubleDerived : ValueBase<Double>(0.5) {
    override var x: Double = 1.25
}

class NullableDerived : ValueBase<String?>(null) {
    override var x: String? = "nullable"
}

fun verify(condition: Boolean) {
    if (!condition) {
        val failure: Any? = null
        failure!!
    }
}

fun main() {
    val derived = Derived()
    val base: Base<String> = derived
    verify(base.x == "child")
    base.x = "OK"
    verify(base.x == "OK")
    verify(derived.x == "OK")

    val reverse = ReverseDerived()
    val reverseBase: ReverseBase<String> = reverse
    verify(reverseBase.x == "reverse")
    reverseBase.x = "also OK"
    verify(reverseBase.x == "also OK")
    verify(reverse.x == "also OK")

    val plain: PlainBase<String> = PlainDerived()
    verify(plain.x == "plain")
    plain.x = "plain OK"
    verify(plain.x == "plain OK")

    val custom: PlainBase<String> = CustomDerived()
    verify(custom.x == "custom")
    custom.x = "OK"
    verify(custom.x == "custom:OK")

    val number: ValueBase<Int> = IntDerived()
    verify(number.x == 2)
    number.x = 42
    verify(number.x == 42)

    val decimal: ValueBase<Double> = DoubleDerived()
    verify(decimal.x == 1.25)
    decimal.x = -0.0
    verify(decimal.x == -0.0)

    val nullable: ValueBase<String?> = NullableDerived()
    verify(nullable.x == "nullable")
    nullable.x = null
    verify(nullable.x == null)
    nullable.x = "restored"
    verify(nullable.x == "restored")
    println("OK")
}
