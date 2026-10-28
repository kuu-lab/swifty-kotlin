// KUU-3129: on a smart-cast receiver (`Feature<T> & BooleanFeature`), reading
// an inherited generic member property substitutes the interface type
// arguments through the concrete implementation
// (`Feature<Boolean>.default` -> `Boolean`).

interface Feature<T : Any> { val default: T }
class BooleanFeature(override val default: Boolean) : Feature<Boolean>
class IntFeature(override val default: Int) : Feature<Int>

fun <T : Any> currentValue(flag: Feature<T>): Boolean {
    if (flag !is BooleanFeature) return false
    val value: Boolean = flag.default
    return value
}

fun <T : Any> currentInt(flag: Feature<T>): Int {
    if (flag is IntFeature) return flag.default
    return -1
}

fun <T : Any> casted(flag: Feature<T>): Boolean {
    val bf = flag as BooleanFeature
    return bf.default
}

fun box(): String {
    if (!currentValue(BooleanFeature(true))) return "FAIL 1"
    if (currentValue(BooleanFeature(false))) return "FAIL 2"
    if (currentValue(IntFeature(3))) return "FAIL 3"
    if (currentInt(IntFeature(7)) != 7) return "FAIL 4"
    if (currentInt(BooleanFeature(true)) != -1) return "FAIL 5"
    if (!casted(BooleanFeature(true))) return "FAIL 6"
    return "OK"
}

fun main() { print(box()) }
