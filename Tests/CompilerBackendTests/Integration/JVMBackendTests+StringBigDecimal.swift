#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func stringToBigDecimalResolvesAndExecutes(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                println("1.5".toBigDecimal().toString())
                println("42".toBigDecimal().toString())
                println("1.5".toBigDecimal() > "1.4".toBigDecimal())
            }
            """, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "1.5\n42\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func stringToBigDecimalAliasAndCallableReferenceResolveAndExecute(mode: EmitMode) throws {
        try withWorkspace { root in
            let runtime = try m11Runtime()
            let classpath = runtime.components(separatedBy: ":")
            let result = try compile("""
            import java.math.BigDecimal
            import kotlin.text.toBigDecimal as parseDecimal

            fun String.toBigDecimal(): BigDecimal = BigDecimal("7")

            fun main() {
                println("1.5".parseDecimal().toString())
                println("42".toBigDecimal().toString())
                val reference: (String) -> BigDecimal = String::parseDecimal
                println(reference("1.4").toString())
                try {
                    println((reference as kotlin.reflect.KFunction<BigDecimal>).call("0.5").toString())
                } catch (error: Throwable) {
                    println(error::class.simpleName)
                }
            }
            """, root: root, mode: mode, classpath: classpath)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let referenceCompilation = try jvmTool(
                "kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root
            )
            try #require(referenceCompilation.exitCode == 0, "\(referenceCompilation.stderr)")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", ([artifact] + classpath).joined(separator: ":"), "HelloKt"])
            let reference = try java([
                "-cp", ([root.appendingPathComponent("reference.jar").path] + classpath).joined(separator: ":"), "HelloKt"
            ])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "1.5\n7\n1.4\nIllegalCallableAccessException\n")
            #expect(execution.stderr.isEmpty)
            #expect(reference.exitCode == 0)
            #expect(reference.stdout == execution.stdout)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
