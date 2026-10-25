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

    @Test(arguments: [false, true])
    func javaClassAssignabilityAndInheritedMethods(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            open class JavaClassBase {
                fun inheritedVisible(): String = "base"
                private fun inheritedHidden(): String = "hidden"
            }

            class JavaClassDerived : JavaClassBase() {
                fun declaredVisible(): String = "derived"
                private fun declaredHidden(): String = "hidden"
            }

            class JavaClassUnrelated

            fun hasMethod(methods: Array<java.lang.reflect.Method>, name: String): Boolean {
                for (method in methods) {
                    if (method.getName() == name) return true
                }
                return false
            }

            fun main() {
                println(JavaClassBase::class.java.isAssignableFrom(JavaClassDerived::class.java))
                println(JavaClassDerived::class.java.isAssignableFrom(JavaClassBase::class.java))
                println(JavaClassDerived::class.java.isAssignableFrom(JavaClassDerived::class.java))
                println(JavaClassBase::class.java.isAssignableFrom(JavaClassUnrelated::class.java))
                println(Any::class.java.isAssignableFrom(JavaClassDerived::class.java))

                val methods = JavaClassDerived::class.java.getMethods()
                println(hasMethod(methods, "declaredVisible"))
                println(hasMethod(methods, "inheritedVisible"))
                println(!hasMethod(methods, "declaredHidden"))
                println(!hasMethod(methods, "inheritedHidden"))

                println("x".javaClass.isInstance("y"))
                println("x".javaClass.simpleName)
                println("x".javaClass.getSimpleName())
            }
            """,
            expectedOutput: """
            true
            false
            true
            false
            true
            true
            true
            true
            true
            true
            String
            String
            """ + "\n",
            moduleName: "KUU3444JavaClassMembers",
            allowDefaultStdlibLibrary: fromArtifact
        )
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
