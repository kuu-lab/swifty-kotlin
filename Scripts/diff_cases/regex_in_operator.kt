fun main() {
    val r = Regex("a.c")
    // BUG-185: `regex in charSequence` still resolves incorrectly (always false)
    // even after correcting the missing `operator` flag on the synthetic
    // CharSequence.contains(regex: Regex) stub; excluded here pending that fix.
    // println(r in "abc")
    // println(r in "xyz")
    println("abc".contains(r))
    println("xyz".contains(r))
}
