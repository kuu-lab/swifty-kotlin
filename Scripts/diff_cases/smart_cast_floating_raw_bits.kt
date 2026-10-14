// KUU-2069: an Any smart cast must unbox a primitive extension receiver.
fun show(value: Any) {
    when (value) {
        is Float -> println(value.toRawBits())
        is Double -> println(value.toRawBits())
    }
}
fun main() {
    println(1.25f.toRawBits())
    println(1.25.toRawBits())
    show(1.25f)
    show(1.25)
}
