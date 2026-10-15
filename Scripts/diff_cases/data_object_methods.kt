data object DataObject {
    data object Nested
}

class Foo {
    data object Inner
}

data object Declared {
    override fun toString() = "Overriden"
}

open class WithFinalToString {
    final override fun toString() = "FinalToString"
}

data object InheritedFromClassWithFinalToString : WithFinalToString()

open class WithOpenToString {
    override fun toString() = "OpenToString"
}

data object InheritedFromClassWithOpenToString : WithOpenToString()

abstract class WithAbstractToString {
    abstract override fun toString(): String
}

data object InheritedFromClassWithAbstractToString : WithAbstractToString()

fun main() {
    println(DataObject.toString())
    println(DataObject.Nested.toString())
    println(Foo.Inner.toString())
    println(Declared.toString())
    println(InheritedFromClassWithFinalToString.toString())
    println(InheritedFromClassWithOpenToString.toString())
    println(InheritedFromClassWithAbstractToString.toString())
    println(DataObject.hashCode() == DataObject.hashCode())
    println(DataObject.hashCode() != DataObject.Nested.hashCode())
    println(DataObject.hashCode() != 0)
    println(DataObject.Nested.hashCode() != 0)
}
