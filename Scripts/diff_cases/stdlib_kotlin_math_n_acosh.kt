import kotlin.math.acosh

private fun reportDouble(label: String, value: Double) {
    val result = acosh(value)
    println("$label ${result.isNaN()} ${result.isInfinite()} ${result == 0.0} ${result > 1.3 && result < 1.4}")
}

private fun reportFloat(label: String, value: Float) {
    val result = acosh(value)
    println("$label ${result.isNaN()} ${result.isInfinite()} ${result == 0.0f} ${result > 1.3f && result < 1.4f}")
}

fun main() {
    reportDouble("D1", 1.0)
    reportDouble("D0", 0.0)
    reportDouble("Dnegative", -1.0)
    reportDouble("DNaN", Double.NaN)
    reportDouble("DpositiveInfinity", Double.POSITIVE_INFINITY)
    reportDouble("DnegativeInfinity", Double.NEGATIVE_INFINITY)
    reportDouble("D2", 2.0)

    reportFloat("F1", 1.0f)
    reportFloat("F0", 0.0f)
    reportFloat("Fnegative", -1.0f)
    reportFloat("FNaN", Float.NaN)
    reportFloat("FpositiveInfinity", Float.POSITIVE_INFINITY)
    reportFloat("FnegativeInfinity", Float.NEGATIVE_INFINITY)
    reportFloat("F2", 2.0f)
}
