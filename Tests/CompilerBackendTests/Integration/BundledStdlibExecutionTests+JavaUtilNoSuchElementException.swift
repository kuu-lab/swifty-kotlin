@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-2296: the Java package spelling shares Kotlin's exception identity.
    @Test(arguments: [false, true], [0, 2])
    func testJavaUtilNoSuchElementExceptionImportConstructsAndCatches(
        allowDefaultStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            """
            import java.util.NoSuchElementException
            import java.util.NoSuchElementException as JavaNoSuchElementException

            fun main() {
                val noArgument = NoSuchElementException()
                check(noArgument.message == null)

                val created = JavaNoSuchElementException("empty")
                val kotlinType: kotlin.NoSuchElementException = created
                check(kotlinType === created)
                check(kotlinType.message == "empty")
                check(kotlinType.toString() == "java.util.NoSuchElementException: empty")

                try {
                    throw created
                } catch (caught: NoSuchElementException) {
                    check(caught === created)
                    println(caught.message)
                }
            }
            """,
            expectedOutput: "empty\n",
            moduleName: "KUU2296JavaUtilNoSuchElementException",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
