import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4423: `KClass.members`/`constructors` handles used to report
    /// `visibility == null` and build `returnType` KTypes from a bare
    /// string descriptor whose classifier resolved to `java.lang.Void`.
    /// Member registration now pins the declared visibility ordinal and a
    /// real KType (classifier, arguments, nullability) on every handle.
    @Test(arguments: [false, true])
    func classMemberVisibilityAndReturnTypeMetadata(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            class VisibilityBox<T>(val v: T) {
                fun publicFn(): Int = 1
                private fun privateFn(): String = "p"
                internal fun internalFn(): T? = null
                protected fun protectedFn(): Boolean = true
                val publicProp: List<Int> = emptyList()
                private val privateProp: T? = null
                fun String.extFn(): Int = length
            }
            fun main() {
                val k = VisibilityBox::class
                val byName = k.members.associateBy { it.name }
                for (n in listOf("publicFn", "privateFn", "internalFn", "protectedFn", "publicProp", "privateProp", "extFn")) {
                    println("$n vis=" + byName[n]?.visibility)
                }
                val publicFn = byName["publicFn"] as kotlin.reflect.KFunction<*>
                println("publicFn rt=" + publicFn.returnType + " cls=" + publicFn.returnType.classifier + " null=" + publicFn.returnType.isMarkedNullable)
                val internalFn = byName["internalFn"] as kotlin.reflect.KFunction<*>
                println("internalFn rt=" + internalFn.returnType + " null=" + internalFn.returnType.isMarkedNullable)
                val publicProp = byName["publicProp"] as kotlin.reflect.KProperty<*>
                println("publicProp rt=" + publicProp.returnType + " args=" + publicProp.returnType.arguments)
                val ctor = k.constructors.first()
                println("ctor rt=" + ctor.returnType + " cls=" + ctor.returnType.classifier + " vis=" + ctor.visibility)
                val extFn = byName["extFn"] as kotlin.reflect.KFunction<*>
                println("extFn rt cls=" + extFn.returnType.classifier + " vis=" + extFn.visibility)
            }
            """,
            expectedOutput: """
            publicFn vis=PUBLIC
            privateFn vis=PRIVATE
            internalFn vis=INTERNAL
            protectedFn vis=PROTECTED
            publicProp vis=PUBLIC
            privateProp vis=PRIVATE
            extFn vis=PUBLIC
            publicFn rt=kotlin.Int cls=class kotlin.Int null=false
            internalFn rt=T? null=true
            publicProp rt=kotlin.collections.List<kotlin.Int> args=[kotlin.Int]
            ctor rt=VisibilityBox<T> cls=class VisibilityBox vis=PUBLIC
            extFn rt cls=class kotlin.Int vis=PUBLIC
            """ + "\n",
            moduleName: "KUU4423ClassMemberVisibility",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
