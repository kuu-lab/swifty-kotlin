#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func overriddenOperatorAndInfixModifiersReachKotlinConsumers(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            open class CallableBase {
                open operator fun get(index: Int): Int = index + 1
                open infix fun join(other: Int): Int = other + 2
            }
            open class CallableMiddle : CallableBase() {
                override fun get(index: Int): Int = index + 10
                override fun join(other: Int): Int = other + 20
            }
            class CallableLeaf : CallableMiddle() {
                override fun get(index: Int): Int = index + 100
                override fun join(other: Int): Int = other + 200
            }
            class PlainCallable {
                fun get(index: Int): Int = index
                fun join(other: Int): Int = other
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let runtime = try m11Runtime()
            try """
            fun main() {
                println(CallableMiddle()[3]); println(CallableMiddle() join 4)
                println(CallableLeaf()[3]); println(CallableLeaf() join 4)
                println(PlainCallable().get(3)); println(PlainCallable().join(4))
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", output.path + ":" + runtime, "-d", "consumer.jar"], root: root)
            let execution = try java(["-Xverify:all", "-cp", root.appendingPathComponent("consumer.jar").path + ":" + output.path + ":" + library.path, "ConsumerKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "13\n24\n103\n204\n3\n4\n")
            #expect(execution.stderr.isEmpty)
            for (expression, modifier) in [("PlainCallable()[3]", "operator"), ("PlainCallable() join 4", "infix")] {
                try "fun rejected() { println(\(expression)) }".write(to: root.appendingPathComponent("invalid.kt"), atomically: true, encoding: .utf8)
                do {
                    _ = try jvmTool("kotlinc", ["invalid.kt", "-cp", output.path + ":" + runtime, "-d", "invalid.jar"], root: root)
                    Issue.record("Unmarked function accepted with \(modifier) syntax")
                } catch CommandRunnerError.nonZeroExit(let error) {
                    #expect(error.exitCode != 0)
                    #expect(error.stderr.contains("'\(modifier)' modifier is required"))
                }
            }
        }
    }
}
#endif
