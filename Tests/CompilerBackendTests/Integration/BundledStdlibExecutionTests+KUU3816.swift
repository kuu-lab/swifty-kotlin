@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test func kuu3816DefinitelyNonNullTypeOfRendersTypeParameter() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KType
            import kotlin.reflect.typeOf

            class C<T> {
                fun list(): KType = typeOf<List<T & Any>>()
                fun map(): KType = typeOf<Map<String, T & Any>>()
                fun nullableList(): KType = typeOf<List<T & Any>?>()
            }
            inline fun <reified R> reifiedList(): KType = typeOf<List<R & Any>>()

            fun main() {
                println(C<Any>().list())
                println(C<Any>().map())
                println(C<Any>().nullableList())
                println(reifiedList<String>())
                println(reifiedList<String?>())
            }
            """,
            expectedOutput: """
            kotlin.collections.List<T>
            kotlin.collections.Map<kotlin.String, T>
            kotlin.collections.List<T>?
            kotlin.collections.List<kotlin.String>
            kotlin.collections.List<kotlin.String?>
            """.trimmingCharacters(in: .newlines) + "\n",
            moduleName: "KUU3816DefinitelyNonNullTypeOf",
            allowDefaultStdlibLibrary: true
        )
    }
}
