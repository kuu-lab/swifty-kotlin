@testable import CompilerCore
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testGenericDelegateFactoryOnObjectExtensionProperty(
        useArtifact: Bool,
        optimization: Int
    ) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlin(
            """
            class D<E, R> {
                operator fun getValue(recv: E, p: Any?): R = "OK" as R
            }
            fun <E, R> mk(): D<E, R> = D()
            object H {
                val Int.s: String by mk()
                fun check(): String = with(this) { 1.s }
            }
            fun main() {
                println(H.check())
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3030GenericDelegateObjectExtensionProperty",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: useArtifact
        )
    }
}
