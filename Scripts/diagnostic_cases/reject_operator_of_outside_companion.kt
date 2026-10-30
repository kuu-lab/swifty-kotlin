// EXPECT-REJECT
// KOTLINC_FLAGS: -Xcollection-literals
operator fun of(vararg s: String) = s.size
fun main() {}
