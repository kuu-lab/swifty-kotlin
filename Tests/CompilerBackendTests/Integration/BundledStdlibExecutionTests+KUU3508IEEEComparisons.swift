import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testGenericFloatingPointComparisonsUseIEEE() throws {
        try compileAndRunKotlin(
            """
            fun <T : Double> genericDoubleEqual(a: T, b: T): Boolean = a == b
            fun <T : Double> genericDoubleNotEqual(a: T, b: T): Boolean = a != b
            fun <T : Double> genericDoubleLess(a: T, b: T): Boolean = a < b
            fun <T : Double> genericDoubleLessOrEqual(a: T, b: T): Boolean = a <= b
            fun <T : Double> genericDoubleGreater(a: T, b: T): Boolean = a > b
            fun <T : Double> genericDoubleGreaterOrEqual(a: T, b: T): Boolean = a >= b
            fun <T : Float> genericFloatEqual(a: T, b: T): Boolean = a == b
            fun <T : Float> genericFloatNotEqual(a: T, b: T): Boolean = a != b
            fun <T : Float> genericFloatLess(a: T, b: T): Boolean = a < b
            fun <T : Float> genericFloatLessOrEqual(a: T, b: T): Boolean = a <= b
            fun <T : Float> genericFloatGreater(a: T, b: T): Boolean = a > b
            fun <T : Float> genericFloatGreaterOrEqual(a: T, b: T): Boolean = a >= b
            fun <T : Double?> genericNullableBoundEqual(a: T, b: T): Boolean = a == b
            fun <A : Double, B : Double?> genericNullableEqual(a: A, b: B): Boolean = a == b

            fun castDoubleEqual(a: Any, b: Any): Boolean = (a as Double) == (b as Double)
            fun castDoubleNotEqual(a: Any, b: Any): Boolean = (a as Double) != (b as Double)
            fun castDoubleLess(a: Any, b: Any): Boolean = (a as Double) < (b as Double)
            fun castNullableDoubleEqual(a: Any?, b: Any?): Boolean = (a as Double?) == (b as Double?)
            fun smartCastDoubleLess(a: Any?, b: Any?): Boolean =
                if (a is Double && b is Double) a < b else false
            fun smartCastNullableDoubleEqual(a: Any?, b: Any?): Boolean =
                if (a is Double? && b is Double?) a == b else false
            fun smartCastNullableDoubleNotEqual(a: Any?, b: Any?): Boolean =
                if (a is Double? && b is Double?) a != b else false
            fun smartCastMixedNullableDoubleEqual(a: Any?, b: Any?): Boolean =
                if (a is Double && b is Double?) a == b else false
            fun smartCastMixedNullableDoubleNotEqual(a: Any?, b: Any?): Boolean =
                if (a is Double && b is Double?) a != b else false

            fun main() {
                println(castDoubleEqual(-0.0, 0.0))
                println(castDoubleNotEqual(-0.0, 0.0))
                println(castDoubleLess(-0.0, 0.0))
                println(castNullableDoubleEqual(-0.0, 0.0))
                println(smartCastDoubleLess(-0.0, 0.0))
                println(smartCastNullableDoubleEqual(-0.0, 0.0))
                println(smartCastNullableDoubleNotEqual(-0.0, 0.0))
                println(smartCastNullableDoubleEqual(Double.NaN, Double.NaN))
                println(smartCastNullableDoubleNotEqual(Double.NaN, Double.NaN))
                println(smartCastNullableDoubleEqual(null, null))
                println(smartCastNullableDoubleEqual(null, 0.0))
                println(smartCastMixedNullableDoubleEqual(-0.0, 0.0))
                println(smartCastMixedNullableDoubleNotEqual(-0.0, 0.0))
                println(smartCastMixedNullableDoubleEqual(-0.0, null))
                println(smartCastMixedNullableDoubleNotEqual(-0.0, null))
                println(genericDoubleEqual(-0.0, 0.0))
                println(genericDoubleNotEqual(-0.0, 0.0))
                println(genericDoubleLess(-0.0, 0.0))
                println(genericDoubleLessOrEqual(-0.0, 0.0))
                println(genericDoubleGreater(-0.0, 0.0))
                println(genericDoubleGreaterOrEqual(-0.0, 0.0))
                println(genericDoubleEqual(Double.NaN, Double.NaN))
                println(genericDoubleNotEqual(Double.NaN, Double.NaN))
                println(genericDoubleLess(Double.NaN, 0.0))
                println(genericDoubleLessOrEqual(Double.NaN, 0.0))
                println(genericDoubleGreater(Double.NaN, 0.0))
                println(genericDoubleGreaterOrEqual(Double.NaN, 0.0))
                println(genericFloatEqual(-0.0f, 0.0f))
                println(genericFloatNotEqual(-0.0f, 0.0f))
                println(genericFloatLess(-0.0f, 0.0f))
                println(genericFloatLessOrEqual(-0.0f, 0.0f))
                println(genericFloatGreater(-0.0f, 0.0f))
                println(genericFloatGreaterOrEqual(-0.0f, 0.0f))
                println(genericFloatEqual(Float.NaN, Float.NaN))
                println(genericFloatNotEqual(Float.NaN, Float.NaN))
                println(genericFloatLess(Float.NaN, 0.0f))
                println(genericFloatLessOrEqual(Float.NaN, 0.0f))
                println(genericFloatGreater(Float.NaN, 0.0f))
                println(genericFloatGreaterOrEqual(Float.NaN, 0.0f))
                println(genericNullableBoundEqual(-0.0, 0.0))
                println(genericNullableBoundEqual(null, null))
                println(genericNullableEqual(-0.0, 0.0))
                println(genericNullableEqual(0.0, null))
                println(genericNullableEqual(Double.NaN, Double.NaN))
            }
            """,
            expectedOutput: "true\nfalse\nfalse\ntrue\nfalse\ntrue\nfalse\nfalse\ntrue\ntrue\nfalse\ntrue\nfalse\nfalse\ntrue\ntrue\nfalse\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\ntrue\ntrue\nfalse\nfalse\n",
            moduleName: "KUU3508IEEEComparisons",
            allowDefaultStdlibLibrary: true,
            requireNoCompilerDiagnostics: true
        )
    }
}
