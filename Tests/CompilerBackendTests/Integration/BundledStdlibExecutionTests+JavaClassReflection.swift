@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func javaClassEnclosingMetadataAndTypeParameterClassifier(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2746_enclosing_members_and_type_parameter.kt", file: #filePath),
            expectedOutput: """
            true
            true
            true
            true
            methodOwner
            true
            true
            true
            true
            true
            true
            true
            U
            INVARIANT
            false
            true
            """ + "\n",
            moduleName: "KUU2746EnclosingMembersAndTypeParameter",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

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

    @Test(arguments: [false, true])
    func javaClassGetDeclaredMethodAtO0(fromArtifact: Bool) throws {
        try assertJavaClassGetDeclaredMethod(fromArtifact: fromArtifact, optimization: 0)
    }

    @Test
    func javaClassGetDeclaredMethodFromArtifactAtO2() throws {
        try assertJavaClassGetDeclaredMethod(fromArtifact: true, optimization: 2)
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

    private func assertJavaClassGetDeclaredMethod(fromArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2381_java_class_get_declared_method.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU2381JavaClassGetDeclaredMethod",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: optLevel
        )
    }
}
