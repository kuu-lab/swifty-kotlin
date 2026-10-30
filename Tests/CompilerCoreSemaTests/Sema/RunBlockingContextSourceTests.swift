@testable import CompilerCore
import Foundation
import RuntimeABI
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct RunBlockingContextSourceTests {
    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return String(decoding: try Data(contentsOf: root.appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/RunBlockingContext/" + name
        )), as: UTF8.self)
    }

    @Test func canonicalSourceHasDefaultContextAndGenericSuspendReceiverBlock() throws {
        let ctx = makeContextFromSource("import kotlinx.coroutines.*\nfun f(): Int = runBlocking { 1 }",
                                        allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let owners = sema.symbols.lookupAll(fqName: ["kotlinx", "coroutines", "runBlocking"].map(ctx.interner.intern))
        let owner = try #require(owners.count == 1 ? owners.first : nil)
        #expect(sema.symbols.isSourceBackedSymbol(owner))
        #expect(sema.symbols.externalLinkName(for: owner) == nil)
        let signature = try #require(sema.symbols.functionSignature(for: owner))
        #expect(signature.parameterTypes.count == 2 && signature.typeParameterSymbols.count == 1)
        #expect(signature.valueParameterHasDefaultValues == [true, false])
        guard case let .classType(context) = sema.types.kind(of: signature.parameterTypes[0]),
              case let .functionType(block) = sema.types.kind(of: signature.parameterTypes[1]) else {
            Issue.record("runBlocking must expose CoroutineContext + suspend receiver block")
            return
        }
        #expect(sema.symbols.symbol(context.classSymbol)?.fqName.map(ctx.interner.resolve)
                == ["kotlin", "coroutines", "CoroutineContext"])
        #expect(block.isSuspend && block.params.isEmpty && block.receiver != nil)
        #expect(block.returnType == signature.returnType)
        let file = try #require(sema.symbols.sourceFileID(for: owner))
        #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlinx/coroutines/Builders.kt")
    }

    @Test(arguments: [false, true])
    func genericResultsStoredCapturesAndReorderedNamesUseCanonicalOwner(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        // Original fixture is byte-identical to the actual Kotlin 2.3.10 JVM control.
        let ctx = makeContextFromSource(try fixture("CompilerControls.kt"), allowDefaultStdlibLibrary: useArtifact)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let owners = sema.symbols.lookupAll(fqName: ["kotlinx", "coroutines", "runBlocking"].map(ctx.interner.intern))
        let owner = try #require(owners.count == 1 ? owners.first : nil)
        if useArtifact {
            #expect(sema.symbols.symbol(owner)?.flags.contains(.importedLibrary) == true,
                    "A source fallback cannot satisfy the artifact lane")
        } else { #expect(sema.symbols.isSourceBackedSymbol(owner)) }
        #expect(sema.symbols.functionSignature(for: owner)?.valueParameterHasDefaultValues == [true, false])
    }

    @Test(arguments: [false, true])
    func bridgePreservesOpaqueSuspendValuesAndExactPhysicalThrowSignature(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        // `.kirDump` elides bundled stdlib bodies, which is where the
        // canonical `runBlocking` calls `__kk_run_blocking_context`. Drive a
        // real emit mode so both lanes materialize the bridge.
        let ctx = makeContextFromSource(try fixture("CompilerControls.kt"),
                                      emit: .executable,
                                      allowDefaultStdlibLibrary: useArtifact)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        try LoweringPhase().run(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let calls = functions.flatMap(\.body).compactMap { instruction -> (String, [KIRExprID])? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else { return nil }
            return (ctx.interner.resolve(callee), arguments)
        }
        let bridges = calls.filter { $0.0 == "__kk_run_blocking_context" }
        try #require(!bridges.isEmpty)
        // The env slot must denote literal 0. Source lowering passes the
        // literal expression itself; artifact bodies decode it as a
        // temporary bound by an earlier constValue/copy — resolve bindings
        // inside the owning function.
        func envPlaceholderIsZero(_ exprID: KIRExprID, in body: [KIRInstruction]) -> Bool {
            var pending = [exprID]
            var seen = Set<KIRExprID>()
            while let current = pending.popLast(), seen.insert(current).inserted {
                if module.arena.expr(current) == .intLiteral(0) { return true }
                for instruction in body {
                    switch instruction {
                    case let .constValue(result, value)
                        where result == current && value == .intLiteral(0):
                        return true
                    case let .copy(source, destination) where destination == current:
                        pending.append(source)
                    default:
                        continue
                    }
                }
            }
            return false
        }
        func bindingsDescription(for exprID: KIRExprID, in body: [KIRInstruction]) -> String {
            body.enumerated().compactMap { index, instruction in
                switch instruction {
                case let .constValue(result, value) where result == exprID:
                    return "[\(index)] constValue r\(result.rawValue) = \(value)"
                case let .copy(source, destination)
                    where destination == exprID || source == exprID:
                    return "[\(index)] copy r\(source.rawValue) -> r\(destination.rawValue)"
                default:
                    return nil
                }
            }.joined(separator: "; ")
        }
        for function in functions {
            for instruction in function.body {
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == "__kk_run_blocking_context"
                else { continue }
                // KIR models outThrown separately; LLVM physical signature adds slot 4.
                #expect(arguments.count == 3)
                if arguments.count == 3 {
                    #expect(
                        envPlaceholderIsZero(arguments[2], in: function.body),
                        "runBlocking bridge env argument must denote literal 0; expr=\(module.arena.expr(arguments[2])); bindings={\(bindingsDescription(for: arguments[2], in: function.body))}"
                    )
                }
            }
        }
        #expect(calls.contains { $0.0 == "kk_suspend_function_create" },
                "Stored/captured suspend values must retain their resumable entry")
        let abi = try #require(RuntimeABISpec.allFunctions.first { $0.name == "__kk_run_blocking_context" })
        #expect(abi.parameters.map(\.type) == [.intptr, .intptr, .intptr, .nullableIntptrPointer])
        #expect(abi.returnType == .intptr && abi.isThrowing)
    }

    @Test(arguments: ["val bad: Int = runBlocking(context = 3) { 1 }",
                      "val body: suspend CoroutineScope.() -> Int = { 1 }; val bad: String = runBlocking(block = body)",
                      "val body: suspend CoroutineScope.(Int) -> Int = { value -> value }; runBlocking(block = body)"])
    func invalidContextStoredResultAndBlockArityAreRejected(body: String) throws {
        let ctx = makeContextFromSource("import kotlinx.coroutines.*\nfun f() { " + body + " }")
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func userHomonymKeepsDeclaredResultAndIsNeverRewrittenToPrivateBridge() throws {
        let ctx = makeContextFromSource("""
        package user1765
        import kotlin.coroutines.*
        import kotlinx.coroutines.CoroutineScope
        fun runBlocking(context: CoroutineContext = EmptyCoroutineContext,
                        block: suspend CoroutineScope.() -> Int): String = "custom"
        fun main() {
            val block: suspend CoroutineScope.() -> Int = { 42 }
            val result: String = runBlocking(block = block)
            println(result)
        }
        """, allowDefaultStdlibLibrary: false)
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let main = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "main"
        })
        #expect(!extractCallees(from: main.body, interner: ctx.interner).contains("__kk_run_blocking_context"))
    }
}
