@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func jvmClassMappingRejectsWrongResults(fromArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try withTemporaryFile(contents: """
        import kotlin.reflect.KClass
        fun wrongKotlin(type: java.lang.Class<String>): KClass<Int> = type.kotlin
        fun wrongPrimitive(type: KClass<Int>): java.lang.Class<Int> = type.javaPrimitiveType
        fun wrongReceiver(value: String) = value.kotlin
        fun main() {}
        """) { path in
            let options = makeTestOptions(
                moduleName: "KUU2062InvalidMapping", inputs: [path],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .executable, allowDefaultStdlibLibrary: fromArtifact, optLevel: optLevel
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(result.exitCode != 0)
            #expect(result.diagnostics.filter { $0.code == "KSWIFTK-TYPE-0001" }.count >= 2)
            #expect(result.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func jvmClassMappingIssue2062(fromArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try compileAndRunKotlin(
            try diffCaseSource("jvm_class_mapping.kt", file: #filePath),
            expectedOutput: String(repeating: "true\n", count: 21) + "null rejected\n",
            moduleName: "KUU2062JvmClassMapping",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: optLevel
        )
    }

    @Test
    func javaClassHandlesAreInternedForSameRuntimeType() throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3274_java_class_identity.kt", file: #filePath),
            expectedOutput: String(repeating: "true\n", count: 6),
            moduleName: "KUU3274JavaClassIdentity",
            allowDefaultStdlibLibrary: true,
            optLevel: .O0
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func jvmClassForNameIssue2379(fromArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2379_class_for_name.kt", file: #filePath),
            expectedOutput: String(repeating: "true\n", count: 5),
            moduleName: "KUU2379ClassForName",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: optLevel
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func jvmClassMappingIssue2391(fromArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        try compileAndRunKotlin(
            try diffCaseSource("java_void_primitive_type.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU2391JavaLangVoid",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: optLevel
        )
    }
}
