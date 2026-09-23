// BUG-C: reading a constructor property (or the built-in name/ordinal) via
// the *implicit* receiver inside an enum member function must see the same
// value an explicit `Color.RED.rgb`-style read does.
enum class Color(val rgb: Int) {
    RED(0xFF0000), GREEN(0x00FF00), BLUE(0x0000FF);
    fun hex() = "#" + rgb.toString(16).padStart(6, '0').uppercase()
}

enum class Dir {
    N, S;
    fun greet() = name.lowercase()
}

fun main() {
    println(Color.RED.hex())
    println(Color.BLUE.rgb)
    println(Dir.N.greet())
}
