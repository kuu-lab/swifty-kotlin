// CANDIDATE-ONLY: indexed writes with a mismatched key type must be compile
// errors. kswiftc used to fall through to the built-in array path and panic at
// runtime; compare the diagnostics with
// kuu_3667_map_indexed_write_keytype.expected.stderr (KUU-3667).
fun main() {
    val m = HashMap<String, String>()
    m[1] = "B"
    m[1] += "B"
}
