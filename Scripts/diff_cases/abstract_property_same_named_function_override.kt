// Regression (KUU-4106): `protected abstract val` declared next to a
// same-named member function was treated as final, so the subclass's
// `override val` was rejected with KSWIFTK-SEMA-FINAL. Properties and
// functions are separate override namespaces in Kotlin — the override must
// target the property and dispatch to the subclass implementation.
abstract class Transaction {
    private val ownerThreadId = 1
    protected abstract val enclosingTransaction: Transaction?
    internal fun enclosingTransaction() = enclosingTransaction
    protected abstract fun endTransaction(successful: Boolean): Int
    internal fun finish(successful: Boolean): Int = endTransaction(successful)
}

class WorkerTransaction(
    override val enclosingTransaction: Transaction?,
) : Transaction() {
    override fun endTransaction(successful: Boolean): Int = if (successful) 1 else 0
}

abstract class Named {
    abstract val tag: String
    fun tag() = tag
}
class Tagged : Named() {
    override val tag: String = "derived"
}

fun main() {
    val t: Transaction = WorkerTransaction(null)
    println(t.enclosingTransaction() == null)
    println(t.finish(true))
    val n: Named = Tagged()
    println(n.tag)
}
