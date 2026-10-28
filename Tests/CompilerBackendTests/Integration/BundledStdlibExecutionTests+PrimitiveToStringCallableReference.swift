import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false], [0, 2])
    func primitiveToStringCallableReference(
        allowDefaultStdlibLibrary: Bool,
        optimizationLevel: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("primitive_tostring_callable_reference.kt", file: #filePath),
            expectedOutput: [
                "true", "false", "true", "true", "toString", "true", "false",
                "true", "false", "true", "false", "true", "false", "null",
                "true", "false", "null", "true", "false", "true", "false",
                "true", "false", "[true, false]", "label", "true", "1", "123", "A", "text",
                "Z", "A", "null", "A", "B",
                "1.5", "-0.0", "1.5", "1.5", "null", "-0.0", "1.5",
                "2.5", "-0.0", "2.5", "2.5", "null", "-0.0", "2.5",
                "-9223372036854775808", "9223372036854775807", "-9223372036854775808",
                "-9223372036854775808", "null", "1", "-9223372036854775808",
                "0", "9223372036854775808", "18446744073709551615", "18446744073709551615",
                "18446744073709551615", "null", "9223372036854775808", "18446744073709551615",
                "4294967295", "255", "65535",
            ].joined(separator: "\n") + "\n",
            moduleName: "KUU3638PrimitiveToStringCallableReference",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimizationLevel == 0 ? .O0 : .O2
        )
    }

    @Test
    func adaptedPrimitiveToStringReferenceIsNotKFunction() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val boolean: (Boolean) -> Unit = Boolean::toString
                val char: (Char) -> Unit = Char::toString
                println(boolean is kotlin.reflect.KFunction<*>)
                println(char is kotlin.reflect.KFunction<*>)
                boolean(true)
                char('A')
                println("done")
            }
            """,
            expectedOutput: "false\nfalse\ndone\n",
            moduleName: "KUU3638AdaptedPrimitiveToStringReference"
        )
    }

    @Test
    func booleanToStringSamReferenceUsesBooleanReceiver() throws {
        try compileAndRunKotlin(
            """
            fun interface Converter {
                fun convert(value: Boolean): String
            }

            fun main() {
                val converter = Converter(Boolean::toString)
                println(converter.convert(true))
                println(converter.convert(false))
            }
            """,
            expectedOutput: "true\nfalse\n",
            moduleName: "KUU3638BooleanToStringSamReference"
        )
    }

    @Test
    func primitiveToStringReferencesInSequences() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(listOf(true, false).asSequence().map(Boolean::toString).toList())
                println(listOf('A', 'B').asSequence().map(Char::toString).toList())
            }
            """,
            expectedOutput: "[true, false]\n[A, B]\n",
            moduleName: "KUU3638PrimitiveToStringSequences"
        )
    }
}
