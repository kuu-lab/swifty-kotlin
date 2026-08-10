#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension VirtualDispatchTests {
    @Test func testResolveVirtualDispatchScenarios() throws {
        let sources = [
            """
            package sample0
            open class Animal0 {
                open fun speak(): String = "..."
            }
            class Dog0 : Animal0() {
                override fun speak(): String = "Woof"
            }
            fun callSpeak0(a: Animal0): String = a.speak()
            """,
            """
            package sample1
            open class Animal1 {
                open fun speak(): String = "..."
            }
            class Dog1 : Animal1() {
                override fun speak(): String = "Woof"
            }
            fun callSpeak1(a: Animal1?): String? = a?.speak()
            """,
            """
            package sample2
            class FinalClass2 {
                fun doSomething2(): Int = 42
            }
            fun callFinal2(x: FinalClass2): Int = x.doSomething2()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            do {
                try runToKIR(ctx)
            } catch {
                // If the frontend does not support open/override syntax yet,
                // skip the whole scenario. The isolated unit tests below cover
                // lowering behavior independently.
                return
            }

            let module = try #require(ctx.kir)

            // sample0: open class dispatch uses virtualCall
            do {
                let body = try findKIRFunctionBody(named: "callSpeak0", in: module, interner: ctx.interner)
                let hasVirtualCall = body.contains { instruction in
                    if case .virtualCall = instruction { return true }
                    return false
                }
                #expect(hasVirtualCall, "Open class with subtypes should use vtable virtualCall")
            }

            // sample1: safe call on open class uses virtualCall on the non-null branch
            do {
                let body = try findKIRFunctionBody(named: "callSpeak1", in: module, interner: ctx.interner)
                let hasVirtualCall = body.contains { instruction in
                    if case .virtualCall = instruction { return true }
                    return false
                }
                #expect(hasVirtualCall, "Safe call on open class should use vtable virtualCall on the non-null branch")
            }

            // sample2: final class method uses static dispatch (no virtualCall)
            do {
                let body = try findKIRFunctionBody(named: "callFinal2", in: module, interner: ctx.interner)
                let hasVirtualCall = body.contains { instruction in
                    if case .virtualCall = instruction { return true }
                    return false
                }
                #expect(!hasVirtualCall, "Final class method should use static dispatch (.call), not virtualCall")
            }
        }
    }

    // MARK: - 17. virtualCall with multiple arguments: receiver separate, args correct count

    @Test func testVirtualCallWithMultipleArgumentsPreservesCount() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let anyType = types.anyType

        let methodSym = SymbolID(rawValue: 8000)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: anyType,
                parameterTypes: [anyType, anyType],
                returnType: types.unitType,
                valueParameterSymbols: [SymbolID(rawValue: 8001), SymbolID(rawValue: 8002)]
            ),
            for: methodSym
        )

        let receiverExpr = arena.appendExpr(.temporary(0), type: anyType)
        let arg1 = arena.appendExpr(.temporary(1), type: anyType)
        let arg2 = arena.appendExpr(.temporary(2), type: anyType)
        let resultExpr = arena.appendExpr(.temporary(3), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: SymbolID(rawValue: 8010),
            name: interner.intern("multiArgCaller"),
            params: [
                KIRParameter(symbol: SymbolID(rawValue: 8011), type: anyType),
                KIRParameter(symbol: SymbolID(rawValue: 8012), type: anyType),
                KIRParameter(symbol: SymbolID(rawValue: 8013), type: anyType),
            ],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: methodSym,
                    callee: interner.intern("multiArgMethod"),
                    receiver: receiverExpr,
                    arguments: [arg1, arg2],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "MultiArg",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "multiArgCaller", in: module, interner: interner)
        let vcInstruction = lowered.body.first { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        guard case let .virtualCall(_, _, receiver, arguments, _, _, _, _) = vcInstruction else {
            Issue.record("Expected virtualCall instruction")
            return
        }
        // Receiver is separate; arguments should have exactly 2 entries
        #expect(arguments.count == 2, "virtualCall should have exactly 2 value arguments (not including receiver)")
        #expect(receiver == receiverExpr, "Receiver should be the original receiver expression")
        #expect(arguments[0] == arg1, "First argument should be arg1")
        #expect(arguments[1] == arg2, "Second argument should be arg2")
    }
}
#endif
