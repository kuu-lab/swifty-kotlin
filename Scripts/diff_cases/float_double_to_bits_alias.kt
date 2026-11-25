// DIFF_JVM
// Aliased imports of Float/Double.toRawBits()/toBits() must resolve to the same
// java.lang.Float/Double bit intrinsics: the JVM lowering keys off the callee
// symbol, not the call-site alias. This file uses only aliased calls because an
// explicit aliased import captures the kotlin.* star-import name, so kotlinc
// rejects mixing alias imports with plain toBits/toRawBits calls in one file.
import kotlin.toBits as aliasedToBits
import kotlin.toRawBits as aliasedToRawBits

fun main() {
    println(1.5.aliasedToBits())
    println(1.5f.aliasedToBits())
    println(1.5.aliasedToRawBits())
    println(1.5f.aliasedToRawBits())
    println((-0.0).aliasedToBits())
    println(Float.NaN.aliasedToBits())
    println(Float.NaN.aliasedToRawBits())
    println(Double.NEGATIVE_INFINITY.aliasedToBits())
    println(Double.POSITIVE_INFINITY.aliasedToRawBits())
}
