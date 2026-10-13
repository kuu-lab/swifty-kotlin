import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func constructorParametersAndCallByDefaults(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            data class WithDefault(val value: String = "fallback")
            class WithRequiredAndDefault(val required: String, val suffix: String = "!")

            fun main() {
                val constructor = WithDefault::class.constructors.single()
                println(constructor.parameters.size)
                val parameter = constructor.parameters.single()
                println(parameter.name)
                println(parameter.isOptional)
                println((constructor.callBy(emptyMap()) as WithDefault).value)

                val mixed = WithRequiredAndDefault::class.constructors.single()
                val instance = mixed.callBy(mapOf(mixed.parameters[0] to "given")) as WithRequiredAndDefault
                println(instance.required + instance.suffix)
            }
            """,
            expectedOutput: "1\nvalue\ntrue\nfallback\ngiven!\n",
            moduleName: "KConstructorCallByDefaults",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
