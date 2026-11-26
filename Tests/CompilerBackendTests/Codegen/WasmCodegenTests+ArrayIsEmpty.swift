@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

extension WasmCodegenTests {
    @Test
    func arrayIsEmptyHelperProducesI64Result() throws {
        guard nodePath() != nil else { return }
        let arena = KIRArena()
        let mainSymbol = SymbolID(rawValue: 1)
        let size = arena.appendExpr(.unit)
        let array = arena.appendExpr(.unit)
        let empty = arena.appendExpr(.unit)
        let body: [KIRInstruction] = [
            .constValue(result: size, value: .intLiteral(0)),
            .call(callee: interner.intern("kk_array_new"), arguments: [size], result: array, canThrow: false),
            .call(callee: interner.intern("kk_array_is_empty"), arguments: [array], result: empty, canThrow: false),
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
        let run = try runUnderNode(bytes)
        #expect(run?.status == 0)
    }

}
