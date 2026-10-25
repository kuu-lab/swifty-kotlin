#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendJvmJavaClassTests {

    @Test
    func testJavaClassInvocationOnAnyReturnsNonNull() throws {
        let source = """
        fun main() {
            val n = 42
            val c = n.javaClass()
            println(c != null)
        }
        """
        try assertKotlinOutput(source, moduleName: "JvmJavaClassTest", expected: "true\n")
    }

    @Test
    func testEnumDeclaringJavaClassReturnsDeclarationForEntriesAndGenericReceivers() throws {
        let source = try diffCaseSource("kuu_3074_enum_declaring_java_class.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "JvmEnumDeclaringJavaClassTest",
            expected: "Direction\nDirection\nDirection\n"
        )
    }

    @Test
    func testLambdaJavaClassEnclosingMetadataMatchesFileFacade() throws {
        let source = """
        val l: Any = {}

        fun box(): String {
            val enclosingClass = l.javaClass.getEnclosingClass()!!.getName()
            if (enclosingClass != "LambdaInPackageKt") return "enclosing class: $enclosingClass"

            val enclosingConstructor = l.javaClass.getEnclosingConstructor()
            if (enclosingConstructor != null) return "enclosing constructor found: $enclosingConstructor"

            val enclosingMethod = l.javaClass.getEnclosingMethod()
            if (enclosingMethod != null) return "enclosing method found: $enclosingMethod"

            val declaringClass = l.javaClass.getDeclaringClass()
            if (declaringClass != null) return "anonymous function has a declaring class: $declaringClass"

            return "OK"
        }

        fun main() { println(box()) }
        """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("lambdaInPackage.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("lambda-in-package").path
        let context = try runCodegenPipeline(
            inputPath: input.path,
            moduleName: "LambdaInPackageTest",
            outputPath: output
        )
        try LinkPhase().run(context)
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.stdout == "OK\n")
    }

    @Test
    func testDesiredAssertionStatusControlStillWorks() throws {
        let source = """
        val l: Any = {}

        fun main() {
            l.javaClass.desiredAssertionStatus()
            println("OK")
        }
        """
        try assertKotlinOutput(source, moduleName: "JvmClassAssertionStatusControl", expected: "OK\n")
    }
}
#endif
