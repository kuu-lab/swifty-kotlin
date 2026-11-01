@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4022: `typeOf` on a reified type parameter must keep the
    /// substituted type's arguments — the hidden reified slot carries the
    /// full KType, not just the erased nominal token — so KType equality is
    /// structural for inline substitutions exactly as on the JVM.
    @Test func kuu4022ReifiedTypeOfKeepsTypeArgumentsForEquality() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KType
            import kotlin.reflect.typeOf

            inline fun <reified T> t() = typeOf<T>()
            inline fun <reified R> t2() = t<R>()
            inline fun <reified T> lt() = typeOf<List<T>>()

            fun main() {
                println(t<String>() == t<String>())
                println(t<List<String>>() == t<List<String>>())
                println(t<List<String>>() == t<List<Int>>())
                println(t<List<String>>() == typeOf<List<String>>())
                println(t<List<String>>() == typeOf<List<Int>>())
                println(t<List<String>?>() == t<List<String>>())
                println(t<Map<String, Int>>() == t<Map<String, String>>())
                println(t<List<List<String>>>() == t<List<List<Int>>>())
                println(t<List<*>>() == t<List<String>>())
                println(t<List<out String>>() == t<List<String>>())
                println(t<List<String>>().hashCode() == typeOf<List<String>>().hashCode())
                println(t2<List<String>>() == t<List<String>>())
                println(lt<String>() == typeOf<List<String>>())
                println(lt<String>() == typeOf<List<Int>>())
                println(t<String>() == t<Int>())
            }
            """,
            expectedOutput: """
            true
            true
            false
            true
            false
            false
            false
            false
            false
            false
            true
            true
            true
            false
            false
            """.trimmingCharacters(in: .newlines) + "\n",
            moduleName: "KUU4022ReifiedTypeOfEquality",
            allowDefaultStdlibLibrary: true
        )
    }

    /// KUU-4022: the reified-KType slot also flows through lambda captures
    /// and still serves `arrayOfNulls<T>`'s component descriptor, so the
    /// erased-allocation metadata path is preserved end to end.
    @Test func kuu4022ReifiedKTypeSurvivesLambdaCaptureAndArrayAllocation() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KType
            import kotlin.reflect.typeOf

            inline fun <reified T> captured(): () -> KType = { typeOf<T>() }
            inline fun <reified T> capturedArr(n: Int): () -> Array<T?> = { arrayOfNulls<T>(n) }

            fun main() {
                println(captured<List<String>>()() == typeOf<List<String>>())
                println(captured<List<String>>()() == typeOf<List<Int>>())
                println(captured<List<Int>?>()().isMarkedNullable)
                println(capturedArr<String>(3)().size)
            }
            """,
            expectedOutput: """
            true
            false
            true
            3
            """.trimmingCharacters(in: .newlines) + "\n",
            moduleName: "KUU4022ReifiedTypeOfCapture",
            allowDefaultStdlibLibrary: true
        )
    }
}
