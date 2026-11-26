import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func companionInitializationFollowsConstructorArgumentEvaluation(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3404_companion_constructor_argument_init_order.kt", file: #filePath),
            expectedOutput: "args;A.<clinit>;A.<init>;\n",
            moduleName: "KUU3404CompanionConstructorArgumentOrder",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
