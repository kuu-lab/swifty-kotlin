// KUU-2207: local generic class type parameters resolve in constructors and members.
fun main() {
    class Local<T>(val value: T)
    println(Local<String>("OK").value)
}
