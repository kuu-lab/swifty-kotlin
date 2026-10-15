fun box() = Class().printSome()

public abstract class AbstractClass<T> {
    public fun printSome() : T = some

    public abstract val some: T
}

public class Class: AbstractClass<String>() {
    public override val some: String
        get() = "OK"
}

abstract class MinimalBase<T> {
    abstract val value: T
    fun read(): T = value
}

class MinimalDerived : MinimalBase<String>() {
    override val value: String get() = "OK"
}

abstract class GenericBase<T> {
    abstract val value: T
}

class GenericDerived : GenericBase<String>() {
    override val value: String get() = "generic"
}

abstract class StringBase {
    abstract val value: String
    fun read(): String = value
}

class StringDerived : StringBase() {
    override val value: String get() = "non-generic"
}

fun main() {
    print(box())
    print("|")
    print(MinimalDerived().read())
    print("|")
    print(GenericDerived().value)
    print("|")
    print(StringDerived().read())
}
