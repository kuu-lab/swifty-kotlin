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

    /// KUU-4064: `val String.ext` / `fun String.extFn()` declared inside a
    /// class are member extensions. Like the JVM, `memberProperties`/
    /// `declaredMemberProperties`/`memberFunctions`/`declaredMemberFunctions`
    /// exclude them, `members` still lists them, and the
    /// `memberExtension*`/`declaredMemberExtension*` accessors in
    /// `kotlin.reflect.full` surface them. Expected output captured from
    /// kotlinc 2.4.20.
    @Test
    func memberExtensionsAreExcludedFromOrdinaryMemberAccessors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()

        let sourcePath = directory.appendingPathComponent("MemberExtensions.kt").path
        let outputPath = directory.appendingPathComponent("MemberExtensions").path
        try """
        import kotlin.reflect.full.*

        class C {
            var String.ext: Int
                get() = length
                set(value) {}
            fun String.extFn(): Int = length
            val normal: Int = 1
            fun normalFn() = 0
        }

        fun main() {
            println(C::class.memberProperties.any { it.name == "ext" })
            println(C::class.declaredMemberProperties.any { it.name == "ext" })
            println(C::class.memberProperties.any { it.name == "normal" })
            println(C::class.declaredMemberExtensionProperties.any { it.name == "ext" })
            println(C::class.memberExtensionProperties.any { it.name == "ext" })
            println(C::class.members.any { it.name == "ext" })
            println(C::class.memberFunctions.any { it.name == "extFn" })
            println(C::class.memberFunctions.any { it.name == "normalFn" })
            println(C::class.memberExtensionFunctions.any { it.name == "extFn" })
            println(C::class.members.any { it.name == "extFn" })
        }
        """.write(toFile: sourcePath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "MemberExtensions",
            inputs: [sourcePath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            stdlibLibraryPath: stdlib
        )
        try assertCompilationSucceeded(
            makeTestDriver().runForTesting(options: options),
            context: "MemberExtensions"
        )

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0)
        // Matches kotlinc 2.4.20 output exactly.
        #expect(result.stdout == """
        false
        false
        true
        true
        true
        true
        false
        true
        true
        true

        """)
    }
}
