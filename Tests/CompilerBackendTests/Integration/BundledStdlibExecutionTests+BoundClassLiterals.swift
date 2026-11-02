import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func boundClassLiteralsIssue1285(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KClass

            fun main() {
                println(Int::class.simpleName)
                println("x"::class.simpleName)
                val s = "a"
                val stringClass: KClass<out String> = s::class
                println(stringClass.simpleName)
                println(5::class.simpleName)
                val listClass: KClass<out List<Int>> = listOf(1)::class
                println(listClass.isInstance(listOf(2)))
                val erased: Any = s
                println(erased::class == String::class)
                try {
                    throw IllegalArgumentException("bound class literal")
                } catch (e: Exception) {
                    println(e::class.simpleName)
                    println(e::class == IllegalArgumentException::class)
                }
            }
            """,
            expectedOutput: "Int\nString\nString\nInt\ntrue\ntrue\nIllegalArgumentException\ntrue\n",
            moduleName: "KUU1285BoundClassLiterals",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    /// KUU-3227: JVM emits one SAM wrapper class per fun interface, so all
    /// `SAM(...)` instances report the same runtime `::class`. The lowering
    /// used to tag each call site's synthesized wrapper with its own class
    /// ID, which interned distinct KClass boxes (`simpleName` fell back to
    /// "Unknown" and equality failed).
    @Test(arguments: [false, true])
    func samWrapperBoundClassLiteralsShareClassIdentity(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            fun interface SAM { fun run() }
            fun interface Other { fun go() }

            fun target(): Unit {}

            fun main() {
                val class1 = (SAM({}) as Any)::class
                val class2 = (SAM({}) as Any)::class
                println(class1 == class2)
                println(class1.simpleName)
                val f = { }
                println((SAM(f) as Any)::class == class1)
                println((SAM(::target) as Any)::class == class1)
                var x = 1
                println((SAM({ x += 1 }) as Any)::class == class1)
                println((Other({}) as Any)::class == class1)
                println(class1 == SAM::class)
                println((SAM({}) as Any) is SAM)
            }
            """,
            expectedOutput: "true\nkk_sam_wrapper_class$SAM\ntrue\ntrue\ntrue\nfalse\nfalse\ntrue\n",
            moduleName: "KUU3227SamWrapperClassIdentity",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    /// KUU-4018: JVM array Class objects are reified per component type, so
    /// `Array<Int>::class != Array<String>::class` while the `kotlin.Array`
    /// nominal name, covariance (`Array<Any>.isInstance(arrayOf(1))`), and
    /// primitive-array identity stay unchanged. The same component
    /// descriptor keys `x::class` on array values and reified `T::class`
    /// captures; `Array<T>::class` on the reified left-hand side erases to
    /// T's bound like `Object[].class` on the JVM.
    @Test(arguments: [false, true])
    func arrayClassLiteralComponentIdentity(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(Array<Int>::class.qualifiedName)
                println(Array<Int>::class.simpleName)
                println(Array<Int>::class == Array<String>::class)
                println(Array<Int>::class == Array<Int>::class)
                println(Array<Int?>::class == Array<Int>::class)
                println(IntArray::class == IntArray::class)
                println(Array<Int>::class.isInstance(arrayOf(1)))
                println(Array<Int>::class.isInstance(arrayOf("x")))
                println(arrayOf(1)::class == Array<Int>::class)
                println(arrayOf(1)::class == Array<String>::class)
                println(intArrayOf(1)::class == IntArray::class)
                println(Array<Array<Int>>::class == Array<Array<String>>::class)
                println(Array<Array<Int>>::class.isInstance(arrayOf(arrayOf(1))))
                println(Array<Array<String>>::class.isInstance(arrayOf(arrayOf(1))))
                println(Array<Any>::class.isInstance(arrayOf(1)))
                println(Array<Int>::class.isInstance(arrayOf<Any>(1)))
                println(classOf<Array<Int>>() == Array<Int>::class)
                println(classOf<Array<Int>>() == Array<String>::class)
                println(classOf<IntArray>() == IntArray::class)
                println(classOf<Array<Int>>() == Array<Int?>::class)
                println(genericArrayClass<Any>() == genericArrayClass<String>())
                println(genericArrayClass<Int>() == Array<Int>::class)
                println(Array<Int>::class.isInstance(42))
                println(IntArray::class.isInstance(arrayOf(1)))
                println(Array<Int>::class.isInstance(null))
            }

            inline fun <reified T> classOf() = T::class
            inline fun <reified T> genericArrayClass() = Array<T>::class
            """,
            expectedOutput: "kotlin.Array\nArray\nfalse\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\nfalse\n"
                + "true\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\ntrue\n"
                + "true\nfalse\nfalse\nfalse\nfalse\n",
            moduleName: "KUU4018ArrayKClassIdentity",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
