open class Base {
    protected val baseField: Int = 1
}

class Derived : Base() {
    fun bumpBase(): Int {
        baseField += 41
        return baseField
    }
}
