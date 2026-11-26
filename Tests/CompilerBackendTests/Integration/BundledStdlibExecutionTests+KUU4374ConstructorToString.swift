@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test func constructorReflectionToStringRendersJvmSignature() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.full.*

            class C(val x: Int) {
                fun df(a: Int): Int = a + x
            }

            fun main() {
                println(C::class.primaryConstructor)
                println(C::class.constructors)
                println(C::x.toString())
                println(C::class.constructors.first().name)
                println(C::df)
            }
            """,
            expectedOutput: """
            fun `<init>`(kotlin.Int): C
            [fun `<init>`(kotlin.Int): C]
            val C.x: kotlin.Int
            <init>
            fun C.df(kotlin.Int): kotlin.Int
            """.trimmingCharacters(in: .newlines) + "\n",
            moduleName: "KUU4374ConstructorToString",
            allowDefaultStdlibLibrary: true
        )
    }
}
