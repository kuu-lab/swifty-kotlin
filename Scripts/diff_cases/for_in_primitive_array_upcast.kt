// KUU-3382: primitive-array loop elements must be boxed when widened to Any
// or Comparable; otherwise Float/Double raw bits escape as reference values.
fun main() {
    var anyDoubles = ""
    for (x: Any in doubleArrayOf(1.0, 2.0)) {
        anyDoubles += "$x;"
    }
    println(anyDoubles)

    var boxedDoubles = ""
    for (x: Any in arrayOf(9.0, 10.0)) {
        boxedDoubles += "$x;"
    }
    println(boxedDoubles)

    var anyFloats = ""
    for (x: Any in floatArrayOf(3.0f, 4.0f)) {
        anyFloats += "$x;"
    }
    println(anyFloats)

    for (x: Comparable<Double> in doubleArrayOf(5.0, 6.0)) {
        println(x.compareTo(5.5))
    }
    for (x: Comparable<Float> in floatArrayOf(7.0f, 8.0f)) {
        println(x.compareTo(7.5f))
    }
}
