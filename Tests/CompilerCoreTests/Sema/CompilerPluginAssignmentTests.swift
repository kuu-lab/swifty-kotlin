#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Built-in and dynamic compiler plugin tests for the Kotlin `assignment` plugin
/// (`org.jetbrains.kotlin.assignment`): rewrites `lhs = rhs` on annotated types
/// into `lhs.assign(rhs)` calls.
@Suite
struct CompilerPluginAssignmentTests {

    private let pluginFlag = "plugin:org.jetbrains.kotlin.assignment:annotation=com.example.SupportsAssignment"
    private let assignmentJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/assignment-compiler-plugin.jar"

    @Test
    func testAssignmentPluginRewritesLocalAndMemberValAssignments() throws {
        let source = """
        package com.example

        annotation class SupportsAssignment

        @SupportsAssignment
        class StringProperty {
            var current: String = ""
            fun assign(value: String) {
                current = value
            }
        }

        class Task {
            val message = StringProperty()
        }

        fun test(): String {
            val localProp = StringProperty()
            localProp = "local-ok"

            val task = Task()
            task.message = "member-ok"
            return localProp.current + ":" + task.message.current
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
            #expect(errors.isEmpty, "Assignment plugin must rewrite val assignments cleanly, got: \(errors.map(\.message))")
            let sema = try #require(ctx.sema)
            #expect(sema.pluginOverloadedAssignments.count == 2, "Expected 2 overloaded assignment expressions recorded in Sema")
        }
    }

    @Test
    func testWithoutAssignmentPluginRejectsValReassignment() throws {
        let source = """
        package com.example

        annotation class SupportsAssignment

        @SupportsAssignment
        class StringProperty {
            fun assign(value: String) {}
        }

        fun test() {
            val prop = StringProperty()
            prop = "hello"
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
            #expect(errors.contains { $0.message.contains("Val cannot be reassigned") })
        }
    }

    @Test
    func testGenericPropertyWithAssignmentPlugin() throws {
        let source = """
        package com.example

        annotation class SupportsAssignment

        @SupportsAssignment
        class Property<T>(var value: T) {
            fun assign(newValue: T) {
                value = newValue
            }
        }

        class Config {
            val port = Property<Int>(8080)
        }

        fun test(): Int {
            val cfg = Config()
            cfg.port = 9090
            return cfg.port.value
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
            #expect(errors.isEmpty, "Generic Property<Int> assignment must succeed, got: \(errors.map(\.message))")
        }
    }

    @Test
    func testDynamicAssignmentJarInspectAndSema() throws {
        guard FileManager.default.fileExists(atPath: assignmentJarPath) else {
            return
        }
        let inspect = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: assignmentJarPath)
        #expect(inspect.pluginId == "org.jetbrains.kotlin.assignment")

        let source = """
        package com.example

        annotation class DynamicAssign

        @DynamicAssign
        class Holder {
            var v: Int = 0
            fun assign(x: Int) { v = x }
        }

        fun test(): Int {
            val h = Holder()
            h = 77
            return h.v
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(assignmentJarPath)",
                "plugin:org.jetbrains.kotlin.assignment:annotation=com.example.DynamicAssign",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Dynamic assignment JAR must rewrite assignment cleanly, got: \(errors.map(\.message))")
        }
    }
}
#endif
