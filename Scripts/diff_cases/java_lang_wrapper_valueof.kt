// KUU-4416: java.lang wrapper valueOf(String/primitive) overloads.
fun main() {
    println(java.lang.Integer.valueOf("5"))
    println(java.lang.Integer.valueOf("ff", 16))
    println(java.lang.Integer.valueOf(5))
    println(java.lang.Long.valueOf("7"))
    println(java.lang.Long.valueOf(7L))
    println(java.lang.Double.valueOf("1.5"))
    println(java.lang.Double.valueOf(2.5))
    println(java.lang.Float.valueOf("1.5"))
    println(java.lang.Byte.valueOf("12"))
    println(java.lang.Short.valueOf("3"))
    println(java.lang.Boolean.valueOf("true"))
}
