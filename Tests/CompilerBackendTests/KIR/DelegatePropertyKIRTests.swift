@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing

@Suite(.serialized)
struct DelegatePropertyKIRTests {
    @Test
    func testLazyFactoryHandleMatchAllowsNonAdjacentCopy() {
        let result = KIRExprID(rawValue: 1)
        let delegateHandle = KIRExprID(rawValue: 2)
        let instructions: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: StringInterner().intern("kotlin.lazy"),
                arguments: [],
                result: result,
                canThrow: false,
                thrownResult: nil
            ),
            .beginBlock,
            .label(7),
            .copy(from: result, to: delegateHandle),
        ]

        #expect(
            ExprLowerer.lazyFactoryResultStoresIntoHandle(
                result: result,
                delegateHandle: delegateHandle,
                callIndex: 0,
                instructions: instructions
            )
        )
    }

    @Test
    func testLazyDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "lazy delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_lazy_create"), "Expected kk_lazy_create in main body, got: \(callees)")
            #expect(callees.contains("kk_lazy_get_value"), "Expected kk_lazy_get_value in main body, got: \(callees)")
        }
    }

    @Test
    func testLazyDelegateGetValueCallIsNonThrowing() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: mainBody, interner: ctx.interner)

            #expect(throwFlags["kk_lazy_create"]?.allSatisfy { $0 == false } == true,
                    "kk_lazy_create should be non-throwing")
            #expect(throwFlags["kk_lazy_get_value"]?.allSatisfy { $0 == false } == true,
                    "kk_lazy_get_value should be non-throwing")
        }
    }

    @Test
    func testExplicitLazyThreadSafetyModesReachRuntimeCreate() throws {
        let source = """
        val top by lazy(LazyThreadSafetyMode.NONE) { 1 }
        class Box {
            val member by lazy(LazyThreadSafetyMode.PUBLICATION) { 2 }
        }
        fun main() {
            val local by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { 3 }
            println(top)
            println(Box().member)
            println(local)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let modeValues = module.arena.declarations.flatMap { declaration -> [Int64] in
                guard case let .function(function) = declaration else { return [] }
                return function.body.compactMap { instruction in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_lazy_create",
                          arguments.count == 2,
                          case let .intLiteral(value)? = module.arena.expr(arguments[1])
                    else {
                        return nil
                    }
                    return value
                }
            }

            #expect(
                modeValues.sorted() == [0, 1, 2],
                "explicit lazy modes should reach kk_lazy_create, got \\(modeValues)"
            )
        }
    }

    @Test
    func testImportedLazyThreadSafetyModeReachesRuntimeCreate() throws {
        let source = """
        import kotlin.LazyThreadSafetyMode.NONE
        val importedNone by lazy(NONE) { 1 }
        fun main() = println(importedNone)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "imported lazy mode should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let module = try #require(ctx.kir)
            let modeValues = module.arena.declarations.flatMap { declaration -> [Int64] in
                guard case let .function(function) = declaration else { return [] }
                return function.body.compactMap { instruction in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_lazy_create",
                          arguments.count == 2,
                          case let .intLiteral(value)? = module.arena.expr(arguments[1])
                    else {
                        return nil
                    }
                    return value
                }
            }
            #expect(modeValues.contains(0), "imported NONE should reach kk_lazy_create as mode 0, got: \(modeValues)")
        }
    }

    @Test
    func testDynamicLazyThreadSafetyModeFallsBackToDefaultRuntimeMode() throws {
        let source = """
        var selectedMode = LazyThreadSafetyMode.NONE
        val top by lazy(selectedMode) { 1 }
        class Box {
            val member by lazy(selectedMode) { 2 }
        }
        fun main() {
            val local by lazy(selectedMode) { 3 }
            println(top)
            println(Box().member)
            println(local)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "dynamic lazy mode should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let module = try #require(ctx.kir)
            let createCalls = module.arena.declarations.flatMap { declaration -> [[KIRExprID]] in
                guard case let .function(function) = declaration else { return [] }
                return function.body.compactMap { instruction in
                    guard case let .call(_, callee, arguments, _, _, _, _, _ ) = instruction,
                          ctx.interner.resolve(callee) == "kk_lazy_create",
                          arguments.count == 2
                    else {
                        return nil
                    }
                    return arguments
                }
            }
            #expect(createCalls.count == 3, "expected three dynamic lazy creates, got: \(createCalls.count)")
            let modeValues = createCalls.compactMap { arguments -> Int64? in
                guard case let .intLiteral(value)? = module.arena.expr(arguments[1]) else {
                    return nil
                }
                return value
            }
            #expect(
                modeValues == Array(repeating: Int64(ctx.options.lazyThreadSafetyMode.rawValue), count: 3),
                "dynamic modes must use the compiler default raw value, got: \(modeValues)"
            )

            let lazyImplConstructors = module.arena.declarations.flatMap { declaration -> [String] in
                guard case let .function(function) = declaration else { return [] }
                return function.body.compactMap { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                    let resolvedCallee = ctx.interner.resolve(callee)
                    return resolvedCallee.contains("LazyImpl") ? resolvedCallee : nil
                }
            }
            #expect(
                lazyImplConstructors.isEmpty,
                "dynamic local lazy lowering must replace the LazyImpl constructor, got: (lazyImplConstructors)"
            )
        }
    }

    @Test
    func testLazyLockOverloadReachesLockAwareRuntimeCreate() throws {
        let source = """
        class Lock
        val sharedLock = Lock()
        val top by lazy(sharedLock) { 1 }
        class Box {
            val member by lazy(sharedLock) { 2 }
        }
        fun main() {
            val local by lazy(sharedLock) { 3 }
            println(top)
            println(Box().member)
            println(local)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "lazy lock overload should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let module = try #require(ctx.kir)
            let lockCreateCalls = module.arena.declarations.flatMap { declaration -> [KIRInstruction] in
                guard case let .function(function) = declaration else { return [] }
                return function.body.filter { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_lazy_create_with_lock"
                }
            }
            #expect(lockCreateCalls.count == 3, "expected lock-aware create for top, member, and local, got (lockCreateCalls.count)")
            for instruction in lockCreateCalls {
                guard case let .call(_, _, arguments, _, _, _, _, _) = instruction else { continue }
                #expect(arguments.count == 3, "lock-aware lazy create should receive initializer, mode, and lock")
            }
        }
    }

    @Test
    func testLocalLazyUnknownLockUsesLockAwareRuntimeCreate() throws {
        let source = """
        fun main() {
            val local by lazy(unknownLock) { 3 }
            println(local)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)
            #expect(
                callees.contains("kk_lazy_create_with_lock"),
                "an unresolved local lazy lock must remain lock-aware, got: \(callees)"
            )
        }
    }

    @Test
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

            #expect(
                !ctx.diagnostics.hasError,
                "observable delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_observable_create"),
                    "Expected kk_observable_create in main body, got: \(callees)")
            #expect(callees.contains("kk_observable_get_value"),
                    "Expected kk_observable_get_value in main body, got: \(callees)")
        }
    }

    @Test
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

            #expect(
                !ctx.diagnostics.hasError,
                "vetoable delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_vetoable_create"), "Expected kk_vetoable_create in main body, got: \(callees)")
            #expect(callees.contains("kk_vetoable_get_value"),
                    "Expected kk_vetoable_get_value in main body, got: \(callees)")
        }
    }

    @Test
    func testCustomDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        val x by myCustomDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("myCustomDelegate"),
                    "Expected delegate constructor/factory call in main body, got: \(callees)")
            #expect(callees.contains("get"), "Expected synthesized property getter call in main body, got: \(callees)")
        }
    }

    @Test
    func testCustomDelegateGetValueCallIsNonThrowing() throws {
        let source = """
        val x by myCustomDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: mainBody, interner: ctx.interner)

            #expect(throwFlags["myCustomDelegate"]?.allSatisfy { $0 == false } == true,
                    "delegate constructor/factory should be non-throwing")
            #expect(throwFlags["get"]?.allSatisfy { $0 == false } == true,
                    "synthesized property getter should be non-throwing")
        }
    }

    @Test
    func testTrailingLambdaDelegatesUseRegularCallArguments() throws {
        let source = """
        class MyLazy<T>(private val initializer: () -> T) {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): T = initializer()
        }
        fun <T> myLazy(initializer: () -> T): MyLazy<T> = MyLazy(initializer)
        val fromConstructor: String by MyLazy { "constructor" }
        val fromFactory: String by myLazy { "factory" }
        fun main() {
            println(fromConstructor)
            println(fromFactory)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "trailing-lambda delegates should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let constructorCalls = module.arena.declarations.flatMap { declaration -> [[KIRExprID]] in
                guard case let .function(function) = declaration else { return [] }
                return function.body.compactMap { instruction in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "MyLazy"
                    else {
                        return nil
                    }
                    return arguments
                }
            }

            #expect(constructorCalls.count >= 2)
            #expect(constructorCalls.allSatisfy { $0.count == 2 })
        }
    }

    @Test
    func testStdlibDelegateLoweringRewritesLazyAccessToGetValue() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_lazy_get_value"),
                    "Expected kk_lazy_get_value after lowering, got: \(callees)")
            #expect(!callees.contains("kk_property_access"),
                    "kk_property_access should be rewritten after StdlibDelegateLowering")
        }
    }

    @Test
    func testStdlibDelegateLoweringRewritesCustomAccessToGetValue() throws {
        let source = """
        val x by unknownDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("get"), "Expected synthesized property getter after lowering, got: \(callees)")
            #expect(!callees.contains("kk_property_access"),
                    "kk_property_access should be rewritten after PropertyLowering")
        }
    }

    @Test
    func testSemaDelegatePropertyWithLazyCompilesWithoutErrors() throws {
        let source = """
        val x: Int by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "val by lazy should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    @Test
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

            #expect(
                !ctx.diagnostics.hasError,
                "var by Delegates.observable should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    @Test
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

            #expect(
                !ctx.diagnostics.hasError,
                "var by Delegates.vetoable should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    @Test
    func testDetectDelegateKindLazyProducesLazyCreate() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_lazy_create"), "lazy delegate should be detected as lazy kind, got: \(callees)")
            #expect(!callees.contains("kk_custom_delegate_create"),
                    "lazy delegate should NOT produce custom delegate create, got: \(callees)")
        }
    }

    @Test
    func testDetectDelegateKindUnknownProducesCustomCreate() throws {
        let source = """
        val x by someUnknownDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("someUnknownDelegate"),
                    "unknown delegate should be detected as custom kind, got: \(callees)")
            #expect(!callees.contains("kk_lazy_create"),
                    "unknown delegate should NOT produce lazy create, got: \(callees)")
        }
    }

    @Test
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

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_notNull_create"),
                    "Delegates.notNull should be detected as notNull kind, got: \(callees)")
            #expect(!callees.contains("kk_custom_delegate_create"),
                    "Delegates.notNull should not fall back to custom delegate create, got: \(callees)")
        }
    }

    @Test
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

            #expect(FileManager.default.fileExists(atPath: outputPath),
                    "Executable should be produced for lazy delegate program")
        }
    }

    @Test
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
                Issue.record("Timed out waiting for delegated property test executable to exit")
                return
            }

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

            #expect(process.terminationStatus != 0, "Reading notNull before assignment should fail")
            if !stderr.isEmpty || !stdout.isEmpty {
                let combined = stderr + stdout
                #expect(
                    combined.contains("IllegalStateException")
                        || combined.contains("fatalError")
                        || combined.contains("initialized before get"),
                    "Unexpected process output: stderr=\(stderr) stdout=\(stdout)"
                )
            }
        }
    }

    @Test
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

            #expect(
                !ctx.diagnostics.hasError,
                "Multiple lazy delegates should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            let createCount = callees.filter { $0 == "kk_lazy_create" }.count
            #expect(createCount >= 2,
                    "Expected at least 2 kk_lazy_create calls for 2 lazy properties, got \(createCount)")
        }
    }

    @Test
    func testDelegatePropertyWithExplicitTypeAnnotation() throws {
        let source = """
        val x: Int by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Delegate with explicit type annotation should compile: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_lazy_create"), "Explicit type annotation should still use lazy create")
            #expect(callees.contains("kk_lazy_get_value"), "Explicit type annotation should still use lazy get_value")
        }
    }
}
