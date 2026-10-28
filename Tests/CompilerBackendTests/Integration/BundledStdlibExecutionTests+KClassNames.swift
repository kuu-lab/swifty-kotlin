import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func classLiteralQualifiedNames(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            package reflectionnames
            import kotlin.reflect.KClass
            import kotlin.reflect.typeOf
            class Outer { class Inner }
            class RuntimeException
            object Named
            class Holder { companion object }
            @OptIn(ExperimentalStdlibApi::class)
            fun main() {
                val exception = kotlin.RuntimeException::class
                val list = List::class
                val ints = IntArray::class
                val pair = Pair::class
                val nothing = Nothing::class
                println(exception.qualifiedName)
                println(list.qualifiedName)
                println(ints.qualifiedName)
                println(pair.qualifiedName)
                println(nothing.qualifiedName)
                println(nothing.simpleName)
                println(String::class.qualifiedName)
                println(Int::class.qualifiedName)
                println(Unit::class.qualifiedName)
                println(Outer.Inner::class.qualifiedName)
                println(Map.Entry::class.qualifiedName)
                println(Array<Int>::class.qualifiedName)
                println(Array<Int>::class.simpleName)
                println(Array<Array<String>>::class.qualifiedName)
                println(RuntimeException::class.qualifiedName)
                println((typeOf<Unit>().classifier as KClass<*>).qualifiedName)
                println(Named::class.qualifiedName)
                println(Holder.Companion::class.qualifiedName)
                class Local
                val anonymous = object {}
                println(Local::class.qualifiedName)
                println(anonymous::class.qualifiedName)
            }
            """,
            expectedOutput: """
            java.lang.RuntimeException
            kotlin.collections.List
            kotlin.IntArray
            kotlin.Pair
            java.lang.Void
            Void
            kotlin.String
            kotlin.Int
            kotlin.Unit
            reflectionnames.Outer.Inner
            kotlin.collections.Map.Entry
            kotlin.Array
            Array
            kotlin.Array
            reflectionnames.RuntimeException
            kotlin.Unit
            reflectionnames.Named
            reflectionnames.Holder.Companion
            null
            null
            """ + "\n",
            moduleName: "KUU1303KClassNames",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
