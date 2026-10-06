// SKIP-DIFF (DEBT-DIFF-001): kotlinc rejects same-module expect/actual declarations because the single-file diff harness cannot model separate common and platform compilations. See docs/diff-skip-inventory.md.
expect abstract class Pool<T : Any>(capacity: Int) {
    protected abstract fun produce(): T
    protected open fun disposeInstance(instance: T)
    fun borrow(): T
}

actual abstract class Pool<T : Any> actual constructor(capacity: Int) {
    protected actual abstract fun produce(): T
    protected actual open fun disposeInstance(instance: T) {}
    actual fun borrow(): T = produce()
}

class IntPool : Pool<Int>(1) {
    override fun produce(): Int = 42
}

fun main() {
    println(IntPool().borrow())
}
