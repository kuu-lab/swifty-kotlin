@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct GenericInterfaceValueClassDefaultArgumentTests {
    @Test
    func inheritedDefaultArgumentWithoutStdlib() throws {
        let source = """
        annotation class JvmInline
        @JvmInline value class IC(val s: String)
        interface IFoo<T> { fun foo(x: T, s: String = "K"): String }
        class FooImpl : IFoo<IC> {
            override fun foo(x: IC, s: String): String = x.s + s
        }
        class Other { fun foo(n: Int = 13): Int = n }
        fun main() {
            val concrete = FooImpl()
            val generic: IFoo<IC> = concrete
            val matches = concrete.foo(IC("O")) == "OK" &&
                generic.foo(IC("O")) == "OK" &&
                concrete.foo(IC("O"), "!") == "O!" &&
                generic.foo(IC("O"), "!") == "O!" && Other().foo() == 13
            val divisor = if (matches) 1 else 0
            val probe = 1 / divisor
        }
        """
        try runFromSource(source, moduleName: "KUU3617NoStdlib", includeStdlib: false, expectedOutput: "")
    }

    @Test(arguments: ["int", "double", "nullable", "reference", "generic", "string"], [0, 2])
    func valueClassBackingsWithoutStdlib(backing: String, optimization: Int) throws {
        let declaration: String
        let valueType: String
        let argument: String
        let condition: String
        var setup = ""
        var extraCondition = "true"
        switch backing {
        case "int":
            declaration = "@JvmInline value class V(val value: Int)"
            valueType = "V"
            argument = "V(42)"
            condition = "x.value == 42"
        case "double":
            declaration = "@JvmInline value class V(val value: Double)"
            valueType = "V"
            argument = "V(-0.0)"
            condition = "x.value == 0.0 && 1.0 / x.value < 0.0"
        case "nullable":
            declaration = "@JvmInline value class V(val value: String?)"
            valueType = "V"
            argument = "V(null)"
            condition = "x.value == null"
        case "reference":
            declaration = "class Payload(val text: String); @JvmInline value class V(val value: Payload)"
            valueType = "V"
            setup = "val payload = Payload(\"X\"); val erased: Any = payload"
            argument = "V(payload)"
            condition = "x.value.text == \"X\""
            extraCondition = "erased is Payload"
        case "generic":
            declaration = "@JvmInline value class V<T : String>(val value: T)"
            valueType = "V<String>"
            argument = "V(\"X\")"
            condition = "x.value == \"X\""
        default:
            declaration = ""
            valueType = "String"
            argument = "\"X\""
            condition = "x == \"X\""
        }
        let source = """
        annotation class JvmInline
        \(declaration)
        fun checkValue(x: \(valueType)): Boolean = \(condition)
        fun <T> identity(value: T): T = value
        interface Check<T> { fun check(x: T, marker: Int = 7): Boolean }
        class Impl : Check<\(valueType)> {
            override fun check(x: \(valueType), marker: Int): Boolean = checkValue(x) && marker > 0
        }
        fun main() {
            \(setup)
            val concrete = Impl()
            val generic: Check<\(valueType)> = concrete
            val matches = concrete.check(\(argument)) && generic.check(\(argument)) &&
                concrete.check(\(argument), 9) && generic.check(\(argument), 9) &&
                checkValue(identity(\(argument))) && (\(extraCondition))
            val divisor = if (matches) 1 else 0
            val probe = 1 / divisor
        }
        """
        try runFromSource(
            source,
            moduleName: "KUU3617NoStdlib_\(backing)",
            includeStdlib: false,
            expectedOutput: "",
            optimization: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    private func runFromSource(
        _ source: String,
        moduleName: String,
        includeStdlib: Bool,
        expectedOutput: String,
        optimization: OptimizationLevel = .O0
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("consumer.kt")
        let output = directory.appendingPathComponent("consumer")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [input.path],
            outputPath: output.path,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: optimization,
            includeStdlib: includeStdlib,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let execution = try CommandRunner.run(executable: output.path, arguments: [], timeout: 10)
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == expectedOutput)
        #expect(execution.stderr.isEmpty)
    }

    @Test
    func inheritedDefaultArgumentFromSource() throws {
        try runInheritedDefaultArgument(allowDefaultStdlibLibrary: false)
    }

    @Test
    func inheritedDefaultArgumentFromArtifact() throws {
        try runInheritedDefaultArgument(allowDefaultStdlibLibrary: true)
    }

    @Test
    func differentValueClassBackingsFromSource() throws {
        try runDifferentValueClassBackings(allowDefaultStdlibLibrary: false)
    }

    @Test
    func differentValueClassBackingsFromArtifact() throws {
        try runDifferentValueClassBackings(allowDefaultStdlibLibrary: true)
    }

    private func runInheritedDefaultArgument(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("value_class_generic_interface_default_arg.kt", file: #filePath)
        let expectedOutput = "OK\nOK\nO!\nO!\n"
        guard allowDefaultStdlibLibrary else {
            try runFromSource(source, moduleName: "KUU3617GenericInterfaceValueClassDefaultArgument", includeStdlib: true, expectedOutput: expectedOutput)
            return
        }
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            source,
            expectedOutput: expectedOutput,
            moduleName: "KUU3617GenericInterfaceValueClassDefaultArgument",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    private func runDifferentValueClassBackings(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("value_class_generic_interface_default_arg_backings.kt", file: #filePath)
        let expectedOutput = "42!\n42!\n-0.0!\n-0.0!\nnull!\nX!\nR!\nR!\nS!\nS!\nG!\nG!\n"
        guard allowDefaultStdlibLibrary else {
            try runFromSource(source, moduleName: "KUU3617GenericInterfaceValueClassBackings", includeStdlib: true, expectedOutput: expectedOutput)
            return
        }
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            source,
            expectedOutput: expectedOutput,
            moduleName: "KUU3617GenericInterfaceValueClassBackings",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
