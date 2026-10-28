import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func builtinArrayReflection(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(ExperimentalUnsignedTypes::class)
            import kotlin.reflect.full.*
            import kotlin.reflect.KVisibility
            fun main() {
                val size = IntArray::class.memberProperties.first { it.name == "size" }
                println(size.returnType.classifier == Int::class)
                println(size.call(intArrayOf(1, 2, 3)) == 3)
                println(IntArray::class.constructors.size == 2)
                println(IntArray::class.primaryConstructor!!.parameters.single().name == "size")
                println(IntArray::class.primaryConstructor!!.visibility == KVisibility.PUBLIC)
                val array = IntArray::class.primaryConstructor!!.call(4)
                println(array.size == 4)
                println(array[0] == 0)
                val get = IntArray::class.memberFunctions.first { it.name == "get" }
                val set = IntArray::class.memberFunctions.first { it.name == "set" }
                set.call(array, 1, 42)
                println(get.call(array, 1) == 42)
                println(array[1] == 42)
                println(IntArray::class.memberFunctions.any { it.name == "clone" })
                println(IntArray::class.memberFunctions.any { it.name == "iterator" })
                println(IntArray::class.declaredMemberFunctions.none { it.name == "equals" })
                println(UIntArray::class.memberFunctions.any { it.name == "contains" })
                val initialized = IntArray::class.constructors.first { it.parameters.size == 2 }.call(3, { i: Int -> i + 1 })
                println(initialized[2] == 3)
                println(Array<Any>::class.primaryConstructor == null)
                println(Array<Any>::class.constructors.single().parameters.size == 2)
                println(UIntArray::class.memberProperties.any { it.name == "size" })
                val storage = UIntArray::class.memberProperties.first { it.name == "storage" }
                println(storage.visibility == KVisibility.INTERNAL)
                println(storage.returnType.classifier == IntArray::class)
                println(UIntArray::class.constructors.size == 2)
                println(UIntArray::class.primaryConstructor!!.parameters.single().name == "storage")
                println(UIntArray::class.primaryConstructor!!.visibility == KVisibility.INTERNAL)
            }
            """,
            expectedOutput: String(repeating: "true\n", count: 22),
            moduleName: "BuiltinArrayReflection",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
