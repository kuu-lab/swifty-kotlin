@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test func kuu2962ReflectionAndTypeOfSupportGaps() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.*
            import kotlin.reflect.typeOf

            class Box<T : Number> {
                @OptIn(kotlin.ExperimentalStdlibApi::class)
                fun listType(): KType = typeOf<List<T>>()
                @OptIn(kotlin.ExperimentalStdlibApi::class)
                fun type(): KType = typeOf<T>()
            }
            class Other<T> {
                @OptIn(kotlin.ExperimentalStdlibApi::class)
                fun type(): KType = typeOf<T>()
            }
            class Outer<A, B> {
                inner class Inner<C, D> {
                    inner class Deep<E, F>
                }
            }

            fun invariant(): MutableList<String> = mutableListOf("x")
            fun contravariant(): MutableList<in String> = throw UnsupportedOperationException()
            fun covariant(): MutableList<out String> = mutableListOf("x")
            fun star(): MutableList<*> = mutableListOf("x")

            class Delegate {
                operator fun getValue(thisRef: Any?, property: KProperty<*>): Int {
                    println(property)
                    println(property.returnType)
                    try {
                        (property as KProperty0<Int>).get()
                    } catch (error: UnsupportedOperationException) {
                        println("caught")
                    }
                    return 42
                }
            }
            class Named(val value: Int)
            class Holder {
                var value: Int = 1
                    private set

                fun inside() = this::value
            }
            fun outside(holder: Holder) = holder::value

            @OptIn(kotlin.ExperimentalStdlibApi::class)
            fun main() {
                val box = Box<Int>()
                val parameter = box.listType().arguments.single().type!!.classifier
                println(parameter is KTypeParameter)
                val reflected = parameter as KTypeParameter
                println(reflected.name)
                println(reflected.isReified)
                println(reflected.variance)
                println(reflected.upperBounds.single())
                println(box.type() == box.type())
                println(box.type() == Other<Int>().type())
                val function = typeOf<(Int) -> String>()
                println(function.arguments.size)
                function.arguments.forEach { println(it.type) }

                println(typeOf<List<String>>().arguments.single().variance)
                val invariantArgument = typeOf<MutableList<Int>>().arguments.single()
                val inputArgument = typeOf<MutableList<in Int>>().arguments.single()
                val outputArgument = typeOf<MutableList<out String>>().arguments.single()
                val starArgument = typeOf<MutableList<*>>().arguments.single()
                println(invariantArgument.variance)
                println(inputArgument.variance)
                println(inputArgument.type)
                println(outputArgument.variance)
                println(outputArgument.type)
                println(starArgument.variance)
                println(starArgument.type)
                val nested = typeOf<Outer<Int, Number>.Inner<String, Float>.Deep<Any, Any?>>()
                println(nested.arguments.size)
                nested.arguments.forEach { println(it.type) }

                println(::invariant.returnType.arguments.single().variance)
                println(::contravariant.returnType.arguments.single().variance)
                println(::covariant.returnType.arguments.single().variance)
                println(::star.returnType.arguments.single().variance)

                val value by Delegate()
                println(value)

                class Local
                val anonymous = object {}
                println(Local::class.qualifiedName)
                println(anonymous::class.qualifiedName)
                println(Named::class.qualifiedName)
                println(Named::class.constructors.single().name)
                println(Holder().inside() is KMutableProperty<*>)
                val outsideProperty = outside(Holder())
                println(outsideProperty is KMutableProperty<*>)
                println(outsideProperty is KProperty<*>)
            }
            """,
            expectedOutput: """
            true
            T
            false
            INVARIANT
            kotlin.Number
            true
            false
            2
            kotlin.Int
            kotlin.String
            INVARIANT
            INVARIANT
            IN
            kotlin.Int
            OUT
            kotlin.String
            null
            null
            6
            kotlin.Any
            kotlin.Any?
            kotlin.String
            kotlin.Float
            kotlin.Int
            kotlin.Number
            INVARIANT
            IN
            OUT
            null
            val value: kotlin.Int
            kotlin.Int
            caught
            42
            null
            null
            Named
            <init>
            true
            false
            true
            """.trimmingCharacters(in: .newlines) + "\n",
            moduleName: "KUU2962ReflectionGaps",
            allowDefaultStdlibLibrary: true
        )
    }
}
