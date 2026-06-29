@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import XCTest

final class DelegatePropertyKIRTests: XCTestCase {

    func testLazyDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "lazy delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lazy_create"),
                          "Expected kk_lazy_create in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("kk_lazy_get_value"),
                          "Expected kk_lazy_get_value in main body, got: \(callees)")
        }
    }

    func testLazyDelegateGetValueCallIsNonThrowing() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: mainBody, interner: ctx.interner)

            XCTAssertEqual(throwFlags["kk_lazy_create"]?.allSatisfy { $0 == false }, true,
                           "kk_lazy_create should be non-throwing")
            XCTAssertEqual(throwFlags["kk_lazy_get_value"]?.allSatisfy { $0 == false }, true,
                           "kk_lazy_get_value should be non-throwing")
        }
    }

    func testObservableDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.observable("initial") { prop, old, new ->
            println("changed")
        }
        fun main() = println(name)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "observable delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_observable_create"),
                          "Expected kk_observable_create in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("kk_observable_get_value"),
                          "Expected kk_observable_get_value in main body, got: \(callees)")
        }
    }

    func testVetoableDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        import kotlin.properties.Delegates
        var count: Int by Delegates.vetoable(0) { prop, old, new ->
            new >= 0
        }
        fun main() = println(count)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "vetoable delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_vetoable_create"),
                          "Expected kk_vetoable_create in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("kk_vetoable_get_value"),
                          "Expected kk_vetoable_get_value in main body, got: \(callees)")
        }
    }

    func testCustomDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        val x by myCustomDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("myCustomDelegate"),
                          "Expected delegate constructor/factory call in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("get"),
                          "Expected synthesized property getter call in main body, got: \(callees)")
        }
    }

    func testCustomDelegateGetValueCallIsNonThrowing() throws {
        let source = """
        val x by myCustomDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: mainBody, interner: ctx.interner)

            XCTAssertEqual(throwFlags["myCustomDelegate"]?.allSatisfy { $0 == false }, true,
                           "delegate constructor/factory should be non-throwing")
            XCTAssertEqual(throwFlags["get"]?.allSatisfy { $0 == false }, true,
                           "synthesized property getter should be non-throwing")
        }
    }

    func testStdlibDelegateLoweringRewritesLazyAccessToGetValue() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lazy_get_value"),
                          "Expected kk_lazy_get_value after lowering, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_property_access"),
                           "kk_property_access should be rewritten after StdlibDelegateLowering")
        }
    }

    func testStdlibDelegateLoweringRewritesCustomAccessToGetValue() throws {
        let source = """
        val x by unknownDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("get"),
                          "Expected synthesized property getter after lowering, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_property_access"),
                           "kk_property_access should be rewritten after PropertyLowering")
        }
    }

    func testSemaDelegatePropertyWithLazyCompilesWithoutErrors() throws {
        let source = """
        val x: Int by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "val by lazy should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testSemaDelegatePropertyWithObservableCompilesWithoutErrors() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.observable("initial") { prop, old, new ->
            println("changed")
        }
        fun main() = println(name)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "var by Delegates.observable should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testSemaDelegatePropertyWithVetoableCompilesWithoutErrors() throws {
        let source = """
        import kotlin.properties.Delegates
        var count: Int by Delegates.vetoable(0) { prop, old, new ->
            new >= 0
        }
        fun main() = println(count)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "var by Delegates.vetoable should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testDetectDelegateKindLazyProducesLazyCreate() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lazy_create"),
                          "lazy delegate should be detected as lazy kind, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_custom_delegate_create"),
                           "lazy delegate should NOT produce custom delegate create, got: \(callees)")
        }
    }

    func testDetectDelegateKindUnknownProducesCustomCreate() throws {
        let source = """
        val x by someUnknownDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("someUnknownDelegate"),
                          "unknown delegate should be detected as custom kind, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_lazy_create"),
                           "unknown delegate should NOT produce lazy create, got: \(callees)")
        }
    }

    func testDetectDelegateKindNotNullProducesNotNullCreate() throws {
        let source = """
        import kotlin.properties.Delegates
        var x: String by Delegates.notNull()
        fun main() {
            x = "hello"
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_notNull_create"),
                          "Delegates.notNull should be detected as notNull kind, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_custom_delegate_create"),
                           "Delegates.notNull should not fall back to custom delegate create, got: \(callees)")
        }
    }

    func testLazyDelegateEndToEndCompilesToExecutable() throws {
        let source = """
        val x by lazy { 42 }
        fun main() {
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LazyDelegateExec",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath),
                          "Executable should be produced for lazy delegate program")
        }
    }

    func testNotNullDelegateReadBeforeAssignmentTrapsWithHelpfulMessage() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.notNull()
        fun main() {
            println(name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NotNullTrapExec",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: outputPath)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                let terminateDeadline = Date().addingTimeInterval(1.0)
                while process.isRunning, Date() < terminateDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    let killDeadline = Date().addingTimeInterval(1.0)
                    while process.isRunning, Date() < killDeadline {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
                XCTFail("Timed out waiting for delegated property test executable to exit")
                return
            }

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

            XCTAssertNotEqual(process.terminationStatus, 0, "Reading notNull before assignment should fail")
            if !stderr.isEmpty || !stdout.isEmpty {
                let combined = stderr + stdout
                XCTAssertTrue(
                    combined.contains("IllegalStateException")
                        || combined.contains("fatalError")
                        || combined.contains("initialized before get"),
                    "Unexpected process output: stderr=\(stderr) stdout=\(stdout)"
                )
            }
        }
    }

    func testMultipleLazyDelegatePropertiesCompileAndLower() throws {
        let source = """
        val a by lazy { 1 }
        val b by lazy { 2 }
        fun main(): Any? = println(a)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Multiple lazy delegates should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            let createCount = callees.filter { $0 == "kk_lazy_create" }.count
            XCTAssertGreaterThanOrEqual(createCount, 2,
                                        "Expected at least 2 kk_lazy_create calls for 2 lazy properties, got \(createCount)")
        }
    }

    func testDelegatePropertyWithExplicitTypeAnnotation() throws {
        let source = """
        val x: Int by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Delegate with explicit type annotation should compile: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lazy_create"),
                          "Explicit type annotation should still use lazy create")
            XCTAssertTrue(callees.contains("kk_lazy_get_value"),
                          "Explicit type annotation should still use lazy get_value")
        }
    }
}
