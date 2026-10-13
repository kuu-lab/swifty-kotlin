package settercontrol1767

class SetterBox {
    var writes: Int = 0
    var value: Int = 1
        set(v) {
            require(v >= 0) { "negative" }
            writes++
            field = v * 2
        }
    var optional: Int? = null
        set(v) {
            writes++
            field = v
        }
    var plain: Int = 0
    var getterCalls: Int = 0
    var setterCalls: Int = 0
    var counted: Int = 5
        get() {
            getterCalls++
            return field
        }
        set(v) {
            setterCalls++
            field = v
        }
    fun updateBare() {
        value += 1
        value++
        plain += 3
    }
}
