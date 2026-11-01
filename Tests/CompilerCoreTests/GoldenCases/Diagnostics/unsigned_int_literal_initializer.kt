package golden.diagnostics

// KUU-3890: unsigned types do not accept unsuffixed (signed) integer
// literals. kotlinc reports initializer/argument type mismatches for every
// one of these; the `u`/`uL` suffix is mandatory. Regression coverage for
// the former intLiteralType coercion that silently typed `.intLiteral`
// expressions as UInt/ULong whenever that was the expected type.

fun takesUInt(x: UInt) = x
fun takesULong(x: ULong) = x

fun main() {
    var a: UInt = 0
    var b: ULong = 0
    var c: UByte = 5
    var d: UShort = 5
    val e: UInt? = 3
    val big: ULong = 5000000000
    val neg: UInt = -1
    var m: UInt = 1u
    m = 9
    val w = takesUInt(7)
    val z = takesULong(7)
    val r: UInt = if (a.toInt() > 0) 1 else 2u
    println("$a $b $c $d $e $big $neg $m $w $z $r")
}
