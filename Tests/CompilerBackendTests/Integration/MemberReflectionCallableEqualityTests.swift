@testable import CompilerCore
import Foundation
import Testing

/// KUU-3806: on the JVM a `KFunction`/`KProperty` obtained through
/// `C::class.members`/`functions`/`memberProperties` equals the unbound
/// `C::member` callable reference. The member reflection handle now records
/// the same equality identity (target, arity, kind, return type, captures)
/// the reference carries, while bound `instance::member` references keep
/// their receiver capture and stay distinct.
@Suite
struct MemberReflectionCallableEqualityTests {
    @Test
    func memberReflectionHandleEqualsUnboundCallableReference() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()

        let sourcePath = directory.appendingPathComponent("MembersEquality.kt").path
        let outputPath = directory.appendingPathComponent("MembersEquality").path
        try """
        import kotlin.reflect.full.*

        class C {
            fun foo() {}
            fun quux(x: Int) {}
            suspend fun susp() {}
            operator fun plus(other: C): C = this
            val bar = 42
            var mutableProp = "m"
        }

        fun main() {
            val c = C()
            println(C::class.functions.find { it.name == "foo" } == C::foo)
            println(C::class.functions.find { it.name == "quux" } == C::quux)
            println(C::class.functions.find { it.name == "susp" } == C::susp)
            println(C::class.functions.find { it.name == "plus" } == C::plus)
            println(C::class.memberProperties.find { it.name == "bar" } == C::bar)
            println(C::class.memberProperties.find { it.name == "mutableProp" } == C::mutableProp)
            println(C::class.members.find { it.name == "foo" } == C::foo)
            println(C::class.members.find { it.name == "bar" } == C::bar)
            println(C::class.functions.find { it.name == "foo" } != c::foo)
            println(C::class.memberProperties.find { it.name == "bar" } != c::bar)
            println(c::foo == c::foo)
            println(c::bar == c::bar)
            println(C::foo != C::quux)
            println(C::foo == C::foo)
            println(c::foo != C()::foo)
            println(C::class.functions.find { it.name == "foo" }?.hashCode() == C::foo.hashCode())
            println(C::class.memberProperties.find { it.name == "bar" }?.hashCode() == C::bar.hashCode())
        }
        """.write(toFile: sourcePath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "MembersEquality",
            inputs: [sourcePath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            stdlibLibraryPath: stdlib
        )
        try assertCompilationSucceeded(
            makeTestDriver().runForTesting(options: options),
            context: "MembersEquality"
        )

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0)
        #expect(result.stdout == String(repeating: "true\n", count: 17))
    }
}
