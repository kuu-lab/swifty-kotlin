// KUU-2272: local subclasses must initialize captures inherited from a local base.
fun foo(s: String): String {
    open class Local {
        fun f() = s
    }
    open class Derived : Local() {
        fun g() = f()
    }
    return Derived().g()
}

fun box(): String = foo("OK")

fun minimalLocalHierarchy(): String {
    val s = "OK"
    open class Local {
        fun f() = s
    }
    class Derived : Local()
    return Derived().f()
}

fun localCaptureWithoutInheritance(): String {
    val s = "OK"
    class Local {
        fun f() = s
    }
    return Local().f()
}

fun inheritedCaptureAcrossSeveralLevels(): String {
    val first = "O"
    val second = "K"
    open class Base {
        fun firstPart() = first
    }
    open class Middle : Base()
    class Derived : Middle() {
        fun secondPart() = second
    }
    val instance = Derived()
    return instance.firstPart() + instance.secondPart()
}

fun inheritedCaptureSurvivesShadowing(): String {
    val value = "base"
    open class Base {
        fun capturedValue() = value
    }
    class Derived(val value: String) : Base()
    val instance = Derived("derived")
    return instance.capturedValue() + "|" + instance.value
}

open class TopLevelBase(val value: String) {
    fun textValue() = value
}

fun localSubclassOfTopLevelBase(): String {
    val value = "OK"
    class Derived : TopLevelBase(value)
    return Derived().textValue()
}

fun main() {
    println(box())
    println(minimalLocalHierarchy())
    println(localCaptureWithoutInheritance())
    println(inheritedCaptureAcrossSeveralLevels())
    println(inheritedCaptureSurvivesShadowing())
    println(localSubclassOfTopLevelBase())
}
