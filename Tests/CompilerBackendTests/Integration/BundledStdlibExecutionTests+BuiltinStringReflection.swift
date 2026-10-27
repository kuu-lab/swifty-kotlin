import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func builtinStringConstructorReflection(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.full.*
            import kotlin.reflect.KProperty1
            fun main() {
                val constructors = String::class.constructors
                println(constructors.size)
                println(constructors.single().call().isEmpty())
                println(String::class.primaryConstructor == null)
                println(Int::class.memberProperties.isEmpty())
                val functions = String::class.memberFunctions
                val properties = String::class.memberProperties
                println(functions.any { it.name == "get" })
                println(properties.any { it.name == "length" })
                val get = functions.first { it.name == "get" }
                println(get.call("abc", 1) == 'b')
                println(get.returnType.classifier == Char::class)
                println(get.parameters.first().type.classifier == String::class)
                println(properties.first { it.name == "length" }.call("abc") == 3)
                @Suppress("UNCHECKED_CAST")
                val length = properties.first { it.name == "length" } as KProperty1<String, *>
                println(length.get("abc") == 3)
            }
            """,
            expectedOutput: "1\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n",
            moduleName: "BuiltinStringConstructorReflection",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
