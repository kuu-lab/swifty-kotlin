import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func builtinPrimitiveCommonMembers(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.full.*
            import kotlin.reflect.KVisibility
            fun main() {
                val functions = Int::class.memberFunctions
                println(functions.isNotEmpty())
                println(functions.first { it.name == "toString" }.call(42))
                println(functions.first { it.name == "equals" }.call(42, 42))
                println(functions.first { it.name == "equals" }.returnType.classifier == Boolean::class)
                println(Int::class.memberProperties.isEmpty())
                println(Int::class.declaredMemberFunctions.none { it.name == "hashCode" })
                println(Boolean::class.memberFunctions.any { it.name == "hashCode" })
                println(UInt::class.memberFunctions.any { it.name == "toString" })
                val plus = functions.first { it.name == "plus" && it.parameters.last().type.classifier == Int::class }
                println(plus.call(2, 3) == 5)
                println(plus.returnType.classifier == Int::class)
                val constructor = Int::class.primaryConstructor!!
                println(constructor.visibility == KVisibility.PRIVATE)
                println(constructor.parameters.isEmpty())
                println(constructor.returnType.classifier == Int::class)
                val data = UInt::class.memberProperties.first { it.name == "data" }
                println(data.visibility == KVisibility.INTERNAL)
                println(data.returnType.classifier == Int::class)
                println(data.call(4294967295u) == -1)
                val uintConstructor = UInt::class.primaryConstructor!!
                println(uintConstructor.parameters.single().type.classifier == Int::class)
                println(uintConstructor.call(-1) == 4294967295u)
                val longPlus = Long::class.memberFunctions.first { it.name == "plus" && it.parameters.last().type.classifier == Long::class }
                println(longPlus.call(2L, 3L) == 5L)
                val increment = Byte::class.memberFunctions.first { it.name == "inc" }
                println(increment.call(127.toByte()) == (-128).toByte())
                val floatPlus = Float::class.memberFunctions.first { it.name == "plus" && it.parameters.last().type.classifier == Float::class }
                println(floatPlus.call(2.0f, 0.5f) == 2.5f)
                val uintPlus = UInt::class.memberFunctions.first { it.name == "plus" && it.parameters.last().type.classifier == UInt::class }
                println(uintPlus.call(4294967295u, 1u) == 0u)
                println(Boolean::class.memberFunctions.first { it.name == "not" }.call(true) == false)
                println(Char::class.memberFunctions.first { it.name == "inc" }.call('a') == 'b')
            }
            """,
            expectedOutput: "true\n42\n" + String(repeating: "true\n", count: 22),
            moduleName: "BuiltinPrimitiveCommonMembers",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
