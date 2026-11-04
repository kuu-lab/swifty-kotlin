package golden.sema

open class Base {
    open fun foo(): Int = 1
    fun bar(): Int = 2
}

class Derived : Base() {
    override fun foo(): Int = 10
}

// 同一モジュール内での internal override は、被 override 側も internal で
// あれば許可される（KUU-4153: public/protected への狭化は kotlinc と同様に拒否）
open class InternalBase {
    internal open fun foo(): Int = 1
}

class InternalDerived : InternalBase() {
    internal override fun foo(): Int = 20
}
