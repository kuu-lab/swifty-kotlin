#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LLVMTerminatedBlockEmissionTests {
    /// KUU-1981: unreachable value producers must not append loads or calls
    /// after a terminator. A subsequent label must still resume emission.
    @Test(arguments: ["constant", "binary", "unary", "nullAssert"], [false, true])
    func unreachableValuesPreserveTerminators(producer: String, returns: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let answer = arena.appendExpr(.intLiteral(42), type: types.intType)
        let deadResult = arena.appendTemporary(type: types.intType)
        let deadInstruction: KIRInstruction
        switch producer {
        case "constant":
            let text = arena.appendExpr(.stringLiteral(interner.intern("unreachable")), type: types.stringType)
            deadInstruction = .constValue(result: text, value: .stringLiteral(interner.intern("unreachable")))
        case "binary":
            deadInstruction = .binary(op: .add, lhs: answer, rhs: answer, result: deadResult)
        case "unary":
            deadInstruction = .unary(op: .unaryPlus, operand: answer, result: deadResult)
        default:
            deadInstruction = .nullAssert(operand: answer, result: deadResult)
        }
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 1), name: interner.intern("answer"), params: [],
            returnType: types.intType,
            body: [
                .constValue(result: answer, value: .intLiteral(42)),
                returns ? .returnValue(answer) : .jump(1),
                deadInstruction,
                .label(1),
                .returnValue(answer),
            ],
            isSuspend: false, isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])], arena: arena
        )
        let backend = try LLVMBackend(
            target: TargetTriple.hostDefault(), optLevel: .O2, debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminated-block-\(UUID().uuidString).ll").path
        defer { try? FileManager.default.removeItem(atPath: output) }

        // O2 runs LLVMVerifyModule before optimization, catching a terminator
        // in the middle of a block even if later passes could erase dead code.
        try backend.emitLLVMIR(module: module, outputIRPath: output, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: output, encoding: .utf8)
        // The stack-overflow guard can merge normal and exceptional returns
        // through a select/phi instead of retaining a literal return.
        #expect(ir.contains("i64 42"))
    }
}
#endif
