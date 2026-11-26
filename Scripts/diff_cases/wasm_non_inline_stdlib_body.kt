// DIFF_WASM
// Non-inline stdlib functions must ship their bodies in the wasm kklib;
// otherwise the call is stubbed to 0 and Boolean results are always false.
fun main() {
    val nullString: String? = null
    println(nullString.isNullOrEmpty())
    val emptySequence: CharSequence? = ""
    println(emptySequence.isNullOrEmpty())
    println("abc".isNullOrEmpty())
    val nullMap: Map<String, Int>? = null
    println(nullMap.isNullOrEmpty())
}
