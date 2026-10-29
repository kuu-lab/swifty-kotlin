// KUU-3743: erased results must be checked at their actual value boundary.
@Suppress("UNCHECKED_CAST")
private fun <T> Any?.uncheckedCast(): T = this as T

private open class Parent
private class Marker : Parent() {
    override fun toString(): String = "marker"
}
private class Target : Parent()
private class AnyBox(var value: Any? = null)
private class GenericBox<T>(var value: T)

private fun returnsAny(): Any? = Marker().uncheckedCast<Int?>()
private fun returnsAnyBlock(): Any? { return Marker().uncheckedCast<Int?>() }
private fun returnsParent(): Parent? = Marker().uncheckedCast<Target?>()
private fun returnsTarget(): Target? = Marker().uncheckedCast<Target?>()
private fun conditionIsTrue(): Boolean = true
private fun <T> invokeBlock(block: () -> T): T = block()
private fun acceptsAny(value: Any?): Boolean = value is Marker
private fun acceptsParent(value: Parent?): Boolean = value is Marker
private fun <T> identity(value: T): T = value
private fun <T> wrongString(): T = Any() as T

fun main() {
    try { println(Marker().uncheckedCast<Int?>()) }
    catch (e: ClassCastException) { println("print:CCE") }
    try {
        val value: Any? = Marker().uncheckedCast<Target?>()
        println("direct-any:" + (value is Marker))
    } catch (e: ClassCastException) { println("direct-any:CCE") }
    try { println("direct-arg:" + acceptsAny(Marker().uncheckedCast<Target?>())) }
    catch (e: ClassCastException) { println("direct-arg:CCE") }
    try {
        val value: Parent? = Marker().uncheckedCast<Target?>()
        println("direct-parent:" + (value is Marker))
    } catch (e: ClassCastException) { println("direct-parent:CCE") }
    try { println("direct-parent-arg:" + acceptsParent(Marker().uncheckedCast<Target?>())) }
    catch (e: ClassCastException) { println("direct-parent-arg:CCE") }
    try {
        val value: Any? = identity(Marker().uncheckedCast<Target?>())
        println("direct-generic:" + (value is Marker))
    } catch (e: ClassCastException) { println("direct-generic:CCE") }
    try { println("wrong-string:" + wrongString<String>().length) }
    catch (e: ClassCastException) { println("wrong-string:CCE") }
    try {
        val value: Any? = Marker().uncheckedCast<Int>()
        println("nonnull-any:" + (value is Marker))
    } catch (e: ClassCastException) { println("nonnull-any:CCE") }
    try {
        val value: Int? = Marker().uncheckedCast<Int?>()
        println("typed-int:" + value)
    } catch (e: ClassCastException) { println("typed-int:CCE") }

    try { println("return-any:" + (returnsAny() is Marker)) }
    catch (e: ClassCastException) { println("return-any:CCE") }
    try { println("return-block:" + (returnsAnyBlock() is Marker)) }
    catch (e: ClassCastException) { println("return-block:CCE") }
    try { println("return-parent:" + (returnsParent() is Marker)) }
    catch (e: ClassCastException) { println("return-parent:CCE") }
    try { println("return-target:" + (returnsTarget() != null)) }
    catch (e: ClassCastException) { println("return-target:CCE") }

    var local: Any? = null
    try {
        local = Marker().uncheckedCast<Int?>()
        println("assign-local:" + (local is Marker))
    } catch (e: ClassCastException) { println("assign-local:CCE") }

    val box = AnyBox()
    try {
        box.value = Marker().uncheckedCast<Int?>()
        println("assign-property:" + (box.value is Marker))
    } catch (e: ClassCastException) { println("assign-property:CCE") }

    val genericBox = GenericBox<Int?>(null)
    try {
        genericBox.value = Marker().uncheckedCast<Int?>()
        println("generic-write:ok")
    } catch (e: ClassCastException) { println("generic-write:CCE") }
    try {
        val typed: Int? = genericBox.value
        println("generic-read:" + typed)
    } catch (e: ClassCastException) { println("generic-read:CCE") }

    try {
        val branch: Any? = if (conditionIsTrue()) Marker().uncheckedCast<Int?>() else null
        println("branch-any:" + (branch is Marker))
    } catch (e: ClassCastException) { println("branch-any:CCE") }
    try {
        val branch: Any? = if (conditionIsTrue()) { Marker().uncheckedCast<Int?>() } else { null }
        println("branch-block:" + (branch is Marker))
    } catch (e: ClassCastException) { println("branch-block:CCE") }

    try {
        val supplier: () -> Any? = { Marker().uncheckedCast<Int?>() }
        println("lambda-any:" + (supplier() is Marker))
    } catch (e: ClassCastException) { println("lambda-any:CCE") }
    try {
        val supplier: () -> Any? = {
            if (conditionIsTrue()) Marker().uncheckedCast<Int?>() else null
        }
        println("lambda-branch:" + (supplier() is Marker))
    } catch (e: ClassCastException) { println("lambda-branch:CCE") }
    try {
        val inferred = { Marker().uncheckedCast<Int?>() }
        val value: Any? = inferred()
        println("lambda-inferred:" + (value is Marker))
    } catch (e: ClassCastException) { println("lambda-inferred:CCE") }
    try {
        val value: Any? = invokeBlock { Marker().uncheckedCast<Int?>() }
        println("lambda-generic:" + (value is Marker))
    } catch (e: ClassCastException) { println("lambda-generic:CCE") }
    try {
        val supplier: () -> Int? = { Marker().uncheckedCast<Int?>() }
        println("lambda-typed:" + supplier())
    } catch (e: ClassCastException) { println("lambda-typed:CCE") }

    val nullAsAny: Any? = null.uncheckedCast<Int>()
    val nullAsInt: Int? = null.uncheckedCast<Int?>()
    val validInt: Int? = 42.uncheckedCast<Int?>()
    println("null-any:" + (nullAsAny == null))
    println("null-int:" + (nullAsInt == null))
    println("valid-int:" + validInt)
}
