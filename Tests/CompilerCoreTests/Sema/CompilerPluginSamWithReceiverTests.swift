#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Built-in and dynamic compiler plugin tests for `sam-with-receiver`
/// (`org.jetbrains.kotlin.samWithReceiver`): converts the first parameter of
/// annotated SAM interfaces into the implicit receiver of SAM lambdas.
@Suite
struct CompilerPluginSamWithReceiverTests {

    private let pluginFlag = "plugin:org.jetbrains.kotlin.samWithReceiver:annotation=com.example.SamWithReceiver"
    private let samJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/sam-with-receiver-compiler-plugin.jar"

    @Test
    func testSamWithReceiverConvertsFirstParameterToImplicitReceiver() throws {
        let source = """
        package com.example

        annotation class SamWithReceiver

        class Box(var value: Int) {
            fun add(delta: Int) { value += delta }
        }

        @SamWithReceiver
        fun interface Action<T> {
            fun execute(target: T)
        }

        fun configure(action: Action<Box>): Int {
            val b = Box(10)
            action.execute(b)
            return b.value
        }

        fun test(): Int {
            return configure {
                this.add(32)
            }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runToLowering(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "sam-with-receiver lambda with `this.add(32)` must compile cleanly, got: \(errors.map(\.message))")
        }
    }

    @Test
    func testWithoutSamWithReceiverRejectsThisMemberCall() throws {
        let source = """
        package com.example

        annotation class SamWithReceiver

        class Box(var value: Int) {
            fun add(delta: Int) { value += delta }
        }

        @SamWithReceiver
        fun interface Action<T> {
            fun execute(target: T)
        }

        fun configure(action: Action<Box>) {}

        fun test() {
            configure {
                this.add(32)
            }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: []
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(!errors.isEmpty, "Without sam-with-receiver plugin, `this.add(32)` must fail")
        }
    }

    @Test
    func testSamWithReceiverWithRemainingParameters() throws {
        let source = """
        package com.example

        annotation class SamWithReceiver

        class Counter(val base: Int) {
            fun sum(extra: Int): Int = base + extra
        }

        @SamWithReceiver
        fun interface Combiner<T, U> {
            fun combine(receiver: T, other: U): Int
        }

        fun runCombine(c: Combiner<Counter, Int>): Int = c.combine(Counter(10), 5)

        fun test(): Int {
            return runCombine { other ->
                sum(other)
            }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runToLowering(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Multi-param sam-with-receiver must pass remaining args properly, got: \(errors.map(\.message))")
        }
    }

    @Test
    func testDynamicSamWithReceiverJarInspectAndSema() throws {
        guard FileManager.default.fileExists(atPath: samJarPath) else {
            return
        }
        let inspect = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: samJarPath)
        #expect(inspect.pluginId == "org.jetbrains.kotlin.samWithReceiver")

        let source = """
        package com.example

        annotation class DynamicSam

        class Target {
            fun ping(): Int = 1
        }

        @DynamicSam
        fun interface Runner {
            fun run(t: Target): Int
        }

        fun exec(r: Runner): Int = r.run(Target())

        fun test(): Int = exec { ping() }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(samJarPath)",
                "plugin:org.jetbrains.kotlin.samWithReceiver:annotation=com.example.DynamicSam",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Dynamic sam-with-receiver JAR must enable receiver lambdas, got: \(errors.map(\.message))")
        }
    }
}
#endif
