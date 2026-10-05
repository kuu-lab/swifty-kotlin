import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testNumericUnaryMemberCalls(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val b: Byte = (-128).toByte()
                println(b.unaryPlus())
                println(b.unaryMinus())
                val nb: Byte? = b
                println(nb?.unaryPlus())
                println(nb?.unaryMinus())
                val zb: Byte? = null
                println(zb?.unaryPlus())
                println(zb?.unaryMinus())
                val s: Short = (-32768).toShort()
                println(s.unaryPlus())
                println(s.unaryMinus())
                val ns: Short? = s
                println(ns?.unaryPlus())
                println(ns?.unaryMinus())
                val zs: Short? = null
                println(zs?.unaryPlus())
                println(zs?.unaryMinus())
                val i: Int = Int.MIN_VALUE
                println(i.unaryPlus())
                println(i.unaryMinus())
                val ni: Int? = i
                println(ni?.unaryPlus())
                println(ni?.unaryMinus())
                val zi: Int? = null
                println(zi?.unaryPlus())
                println(zi?.unaryMinus())
                val l: Long = Long.MIN_VALUE
                println(l.unaryPlus())
                println(l.unaryMinus())
                val nl: Long? = l
                println(nl?.unaryPlus())
                println(nl?.unaryMinus())
                val zl: Long? = null
                println(zl?.unaryPlus())
                println(zl?.unaryMinus())
                val f: Float = 5.5f
                println(f.unaryPlus())
                println(f.unaryMinus())
                val nf: Float? = f
                println(nf?.unaryPlus())
                println(nf?.unaryMinus())
                val zf: Float? = null
                println(zf?.unaryPlus())
                println(zf?.unaryMinus())
                val d: Double = 5.5
                println(d.unaryPlus())
                println(d.unaryMinus())
                val nd: Double? = d
                println(nd?.unaryPlus())
                println(nd?.unaryMinus())
                val zd: Double? = null
                println(zd?.unaryPlus())
                println(zd?.unaryMinus())
                println(5.unaryPlus())
                println(5.unaryMinus())
                println(5.5.unaryMinus())
                println(0.0.unaryMinus().toRawBits() == (-0.0).toRawBits())
                println(0.0f.unaryMinus().toRawBits() == (-0.0f).toRawBits())
                println((-0.0).unaryMinus().toRawBits() == 0.0.toRawBits())
                println((-0.0f).unaryPlus().toRawBits() == (-0.0f).toRawBits())
                println(Double.POSITIVE_INFINITY.unaryMinus() == Double.NEGATIVE_INFINITY)
                println(Float.NaN.unaryMinus().isNaN())
            }
            """,
            expectedOutput: "-128\n128\n-128\n128\nnull\nnull\n-32768\n32768\n-32768\n32768\nnull\nnull\n-2147483648\n-2147483648\n-2147483648\n-2147483648\nnull\nnull\n-9223372036854775808\n-9223372036854775808\n-9223372036854775808\n-9223372036854775808\nnull\nnull\n5.5\n-5.5\n5.5\n-5.5\nnull\nnull\n5.5\n-5.5\n5.5\n-5.5\nnull\nnull\n5\n-5\n-5.5\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n",
            moduleName: "KUU1259NumericUnaryMemberCalls",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
