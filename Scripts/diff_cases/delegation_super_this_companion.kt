// KUU-4517: inside a supertype/constructor delegation specifier the
// superclass's companion object is the innermost implicit receiver, so an
// unqualified `this` binds to it (and its members resolve unqualified)
// rather than to an enclosing receiver.
open class Base(val selected: String) {
    constructor(value: Any?) : this("any")
    constructor(value: Companion) : this("companion")
    companion object {
        val TAG = "tag"
    }
}

class TopLevel : Base(this)
class TopLevelTag : Base(TAG)

fun Base.localClass(): String {
    class Sub : Base(this)
    return Sub().selected
}

fun Base.objectLiteral(): String = object : Base(this) {}.selected

class Secondary : Base {
    constructor() : super(this)
}

enum class Entry(val s: String) {
    A(this);
    constructor(v: Any?) : this("any")
    constructor(v: Companion) : this("companion")
    companion object
}

open class NoCompanion(val value: Any?)
fun Base.fallback(): Boolean = object : NoCompanion(this) {}.value is Base

fun main() {
    println(TopLevel().selected)
    println(TopLevelTag().selected)
    println(Base("x").localClass())
    println(Base("x").objectLiteral())
    println(Secondary().selected)
    println(Entry.A.s)
    println(Base("x").fallback())
}
