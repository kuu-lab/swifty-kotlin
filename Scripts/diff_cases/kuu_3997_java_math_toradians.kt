// KUU-3997: java.lang.Math.toRadians must match the JDK bit-for-bit.
// The JDK evaluates degrees * (PI / 180); (degrees / 180) * PI differs in
// the last ulp for inputs like 1e10.
fun main() {
    val degrees = doubleArrayOf(
        0.0, 1.0, 45.0, 90.0, 123.456, 180.0, 360.0, -45.0,
        1e10, Double.MIN_VALUE, 1e-300, 359.999, 1e15
    )
    for (d in degrees) {
        println("$d -> " + Math.toRadians(d))
    }
    println(Math.toDegrees(Math.toRadians(123.456)))
}
