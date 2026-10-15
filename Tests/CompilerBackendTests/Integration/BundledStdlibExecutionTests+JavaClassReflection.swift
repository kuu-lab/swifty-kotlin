@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    // Source-mode O2 is tracked by KUU-2241: even a trivial source-mode program
    // currently fails LLVM verification on a high-arity function invocation.
    @Test(arguments: [false, true])
    func javaClassGetDeclaredMethodsAtO0(fromArtifact: Bool) throws {
        try assertJavaClassGetDeclaredMethods(fromArtifact: fromArtifact, optimization: 0)
    }

    @Test
    func javaClassGetDeclaredMethodsFromArtifactAtO2() throws {
        try assertJavaClassGetDeclaredMethods(fromArtifact: true, optimization: 2)
    }

    private func assertJavaClassGetDeclaredMethods(fromArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2377_java_class_get_declared_methods.kt", file: #filePath),
            expectedOutput: "true\ntrue\ntrue\n",
            moduleName: "KUU2377JavaClassGetDeclaredMethods",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: optLevel
        )
    }
}
