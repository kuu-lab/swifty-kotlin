// KUU-4578: `by mapOf()` has no arguments to pin the factory type parameters;
// the delegate convention (Map.getValue's `V1 : V` bound) must still infer
// K = String and V = property type, matching kotlinc.
fun main() {
    try {
        val w: Int by mapOf()
        println(w)
    } catch (e: NoSuchElementException) {
        println(e.message)
    }
    try {
        val s: String by mapOf()
        println(s)
    } catch (e: NoSuchElementException) {
        println(e.message)
    }
}
