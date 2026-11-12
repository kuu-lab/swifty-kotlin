@testable import CompilerBackend
@testable import CompilerCore
import Testing

extension WasmCodegenTests {
    // Regression: `$__kk_wasm_alloc` must grow linear memory geometrically
    // (at least 16 pages / doubling) rather than 1 page at a time, so repeated
    // allocations do not stall or hit VMA/SIGSEGV limits under Node/V8.
    @Test
    func repeatedAllocationsCompleteUnderNodeWithoutPageByPageGrow() throws {
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)

        let counter = arena.appendExpr(.unit)
        let zero = arena.appendExpr(.unit)
        let one = arena.appendExpr(.unit)
        let limit = arena.appendExpr(.unit)
        let cond = arena.appendExpr(.unit)
        let wordCount = arena.appendExpr(.unit)
        let typeID = arena.appendExpr(.unit)
        let obj = arena.appendExpr(.unit)
        let nextCounter = arena.appendExpr(.unit)
        let okStr = arena.appendExpr(.unit)

        let loopLabel: Int32 = 100
        let exitLabel: Int32 = 101

        let body: [KIRInstruction] = [
            .constValue(result: zero, value: .intLiteral(0)),
            .constValue(result: one, value: .intLiteral(1)),
            .constValue(result: limit, value: .intLiteral(2000)),
            .constValue(result: wordCount, value: .intLiteral(256)),
            .constValue(result: typeID, value: .intLiteral(1)),
            .copy(from: zero, to: counter),
            .label(loopLabel),
            .call(
                callee: interner.intern("kk_op_lt"),
                arguments: [counter, limit],
                result: cond,
                canThrow: false
            ),
            .jumpIfEqual(lhs: cond, rhs: zero, target: exitLabel),
            .call(
                callee: interner.intern("kk_object_new"),
                arguments: [wordCount, typeID],
                result: obj,
                canThrow: false
            ),
            .call(
                callee: interner.intern("kk_op_add"),
                arguments: [counter, one],
                result: nextCounter,
                canThrow: false
            ),
            .copy(from: nextCounter, to: counter),
            .jump(loopLabel),
            .label(exitLabel),
            .constValue(result: okStr, value: .stringLiteral(interner.intern("ok"))),
            .call(
                callee: interner.intern("__kk_println_raw"),
                arguments: [okStr],
                result: nil,
                canThrow: false
            ),
            .returnUnit,
        ]

        let function = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: TypeID(rawValue: 0),
            body: body,
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])],
            arena: arena
        )

        let bytes = try emit(module, entry: mainSymbol)
        if let run = try runUnderNode(bytes) {
            #expect(run.status == 0)
            #expect(run.stdout == "ok\n")
        }
    }
}
