@Suppress("UNCHECKED_CAST")
private fun <T> Any?.uncheckedCast(): T = this as T

private open class Parent {
    open fun label(): String = "parent"
}

private class Marker : Parent() {
    override fun label(): String = "marker"
    override fun toString(): String = "marker"
}

private class Target : Parent()

private fun acceptsAny(value: Any?): Boolean = value is Marker
private fun acceptsParent(value: Parent?): String = value?.label() ?: "null"
private fun <T> identity(value: T): T = value

fun main() {
    try {
        println(Marker().uncheckedCast<Int?>())
    } catch (e: ClassCastException) {
        println("print:CCE")
    }

    try {
        val value: Any? = Marker().uncheckedCast<Target?>()
        println("any-local:" + (value is Marker))
    } catch (e: ClassCastException) {
        println("any-local:CCE")
    }

    try {
        println("any-argument:" + acceptsAny(Marker().uncheckedCast<Target?>()))
    } catch (e: ClassCastException) {
        println("any-argument:CCE")
    }

    try {
        val value: Parent? = Marker().uncheckedCast<Target?>()
        println("parent-local:" + value?.label())
    } catch (e: ClassCastException) {
        println("parent-local:CCE")
    }

    try {
        println("parent-argument:" + acceptsParent(Marker().uncheckedCast<Target?>()))
    } catch (e: ClassCastException) {
        println("parent-argument:CCE")
    }

    try {
        val value: Any? = identity(Marker().uncheckedCast<Target?>())
        println("generic-argument:" + (value is Marker))
    } catch (e: ClassCastException) {
        println("generic-argument:CCE")
    }

    try {
        val value: Target? = Marker().uncheckedCast<Target?>()
        println("typed:" + (value != null))
    } catch (e: ClassCastException) {
        println("typed:CCE")
    }

    try {
        val value: Int? = Marker().uncheckedCast<Int?>()
        println("int:" + value)
    } catch (e: ClassCastException) {
        println("int:CCE")
    }

    try {
        val value: Any? = Marker().uncheckedCast<Int>()
        println("nonnull-any:" + (value is Marker))
    } catch (e: ClassCastException) {
        println("nonnull-any:CCE")
    }

    val valid: Int? = 42.uncheckedCast<Int?>()
    val absent: Int? = null.uncheckedCast<Int?>()
    println("valid:" + valid)
    println("null:" + (absent == null))
}
