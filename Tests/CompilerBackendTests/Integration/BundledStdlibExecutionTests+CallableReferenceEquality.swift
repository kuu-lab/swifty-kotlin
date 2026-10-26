import Testing

extension BundledStdlibExecutionTests {
    @Test
    func identicalFunInterfaceConstructorReferencesCompareEqual() throws {
        try compileAndRunKotlin(
            """
            fun interface KSupplier<out R> { fun get(): R }

            val ks1: (() -> String) -> KSupplier<String> = ::KSupplier
            val ks2: (() -> String) -> KSupplier<String> = ::KSupplier

            fun main() {
                println(ks1 == ks2)
                println(ks1.hashCode() == ks2.hashCode())
            }
            """,
            expectedOutput: "true\ntrue\n",
            moduleName: "KUU3362FunInterfaceConstructorReferenceEquality"
        )
    }

    @Test(arguments: [true, false])
    func sameOverloadedFunctionReferenceComparesEqual(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("callable_reference_equality_overload.kt", file: #filePath),
            expectedOutput: "true\ntrue\nfalse\n",
            moduleName: "KUU2101CallableReferenceEquality",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func contextualCallableReferencesCompareCapturedContextValues(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3309_contextual_callable_reference_equality.kt", file: #filePath),
            expectedOutput: "true\ntrue\nfalse\nA1\ntrue\ntrue\nfalse\nA1\n",
            moduleName: "KUU3309ContextualCallableReferenceEquality",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
