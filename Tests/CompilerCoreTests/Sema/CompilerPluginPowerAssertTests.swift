#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Built-in and dynamic compiler plugin tests for `power-assert`
/// (`org.jetbrains.kotlin.powerassert`): rewrites assertion calls to capture
/// sub-expressions and render a diagnostic value diagram on failure.
@Suite
struct CompilerPluginPowerAssertTests {

    private let pluginFlag = "plugin:org.jetbrains.kotlin.powerassert:function=kotlin.require"
    private let powerAssertJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/power-assert-compiler-plugin.jar"

    @Test
    func testPowerAssertRecordsCallAndCapturesInSemaAndKIR() throws {
        let source = """
        package com.example

        fun checkSum(a: Int, b: Int, c: Int) {
            require(a + b == c)
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
            #expect(errors.isEmpty, "Power-assert compilation must succeed cleanly, got: \(errors.map(\.message))")

            let sema = try #require(ctx.sema)
            #expect(sema.powerAssertCalls.count == 1, "Expected 1 power-assert call recorded in Sema")
            let callInfo = try #require(sema.powerAssertCalls.values.first)
            #expect(callInfo.callLineText.contains("require(a + b == c)"))
            #expect(callInfo.captureExprs.count >= 4, "Expected captures for a, +, b, ==, c, got: \(callInfo.captureExprs.count)")
        }
    }

    @Test
    func testPowerAssertSkipsCallWithExplicitMessageLambda() throws {
        let source = """
        package com.example

        fun checkSum(a: Int, b: Int) {
            require(a == b) { "explicit custom message" }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: [pluginFlag]
            )
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            #expect(sema.powerAssertCalls.isEmpty, "Call with explicit message lambda must not be rewritten")
        }
    }

    @Test
    func testDynamicPowerAssertJarInspectAndSema() throws {
        guard FileManager.default.fileExists(atPath: powerAssertJarPath) else {
            return
        }
        let inspect = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: powerAssertJarPath)
        #expect(inspect.pluginId == "org.jetbrains.kotlin.powerassert")
        #expect(inspect.options.contains(where: { $0.name == "function" }))

        let source = """
        package com.example

        fun testAssert(x: Int, y: Int) {
            assert(x == y)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(powerAssertJarPath)",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runToLowering(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Dynamic power-assert JAR must compile cleanly, got: \(errors.map(\.message))")
            let sema = try #require(ctx.sema)
            #expect(sema.powerAssertFunctions.contains("kotlin.assert"))
            #expect(sema.powerAssertCalls.count == 1)
        }
    }
}
#endif
