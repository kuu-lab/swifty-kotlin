@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-3895: a `Nothing` type inside `typeOf` must render the Kotlin type
    /// name `kotlin.Nothing` even though its classifier is `java.lang.Void`
    /// (`Nothing::class == Void::class` on the JVM). The token-0 KClass cache
    /// must also keep distinct name hints apart: `Nothing?` lowers with the
    /// `kotlin.Nothing` hint while `Nothing` uses `java.lang.Void`.
    @Test func kuu3895TypeOfNothingRendersKotlinName() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KClass
            import kotlin.reflect.typeOf
            import kotlin.reflect.full.starProjectedType

            fun main() {
                println(typeOf<Nothing?>())
                println(typeOf<List<Nothing>>())
                println(typeOf<List<Nothing?>>())
                println(typeOf<Map<String, Nothing>>())
                val classifier = typeOf<List<Nothing>>().arguments[0].type!!.classifier as KClass<*>
                println(classifier)
                println(classifier.qualifiedName)
                println(classifier.simpleName)
                println(classifier == Nothing::class)
                println(Nothing::class)
                println(Nothing::class.qualifiedName)
                println(Nothing::class.simpleName)
                println(Nothing::class.starProjectedType)
                println(kotlin.RuntimeException::class)
                println(typeOf<List<java.lang.Void?>>())
            }
            """,
            expectedOutput: """
            kotlin.Nothing?
            kotlin.collections.List<kotlin.Nothing>
            kotlin.collections.List<kotlin.Nothing?>
            kotlin.collections.Map<kotlin.String, kotlin.Nothing>
            class java.lang.Void
            java.lang.Void
            Void
            true
            class java.lang.Void
            java.lang.Void
            Void
            java.lang.Void
            class java.lang.RuntimeException
            kotlin.collections.List<java.lang.Void?>
            """.trimmingCharacters(in: .newlines) + "\n",
            moduleName: "KUU3895TypeOfNothing",
            allowDefaultStdlibLibrary: true
        )
    }
}
