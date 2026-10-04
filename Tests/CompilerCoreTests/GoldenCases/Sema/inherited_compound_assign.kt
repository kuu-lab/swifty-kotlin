package golden.sema

open class Base {
    protected var baseField: Int = 1
}

class Derived : Base() {
    fun bumpBase(): Int {
        baseField += 41
        return baseField
    }

    fun incBase(): Int {
        baseField++
        return baseField
    }
}

open class GrandParent {
    protected var gpField: Int = 1
}

open class Parent : GrandParent()

class Child : Parent() {
    fun bumpGrandparentField(): Int {
        gpField += 1
        return gpField
    }
}
