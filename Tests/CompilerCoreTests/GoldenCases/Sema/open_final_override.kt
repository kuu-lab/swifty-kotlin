package golden.sema

open class Base {
    open fun foo(): Int = 1
    fun bar(): Int = 2
}

class Derived : Base() {
    override fun foo(): Int = 10
}

// 同一モジュール内での internal override は許可（モジュール FQN 比較で検証）
class InternalDerived : Base() {
    internal override fun foo(): Int = 20
}
