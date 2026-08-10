// A user-defined top-level `Error` class must not shadow `kotlin.Error` when the
// bundled `NotImplementedError` declaration is injected for TODO().
class Error(val label: String)

fun main() {
    println(Error("shadow").label)
    try {
        TODO("shadowed")
    } catch (e: NotImplementedError) {
        println(e.message)
    }
}
