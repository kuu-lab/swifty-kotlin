#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FlatStringRuntimeDeclarationTests {
    @Test(arguments: ["__kk_locale_toString_flat", "kk_string_to_flat"], [true, false])
    func addressesAndCallsUseTheSamePointerReturn(calleeName: String, addressFirst: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let callee = interner.intern(calleeName)
        let handle = arena.appendExpr(.intLiteral(0), type: types.intType)
        let address = arena.appendExpr(.externSymbolAddress(callee), type: types.intType)
        let result = arena.appendExpr(.temporary(0), type: types.stringType)
        let addressInstruction = KIRInstruction.constValue(result: address, value: .externSymbolAddress(callee))
        let callInstruction = KIRInstruction.call(
            callee: callee, arguments: [handle], result: result,
            canThrow: false
        )
        // Each body has its own declaration cache, while LLVM functions are
        // shared by the module. Names control the emitter's sorted body order.
        let addressFunction = KIRFunction(
            symbol: SymbolID(rawValue: 1904),
            name: interner.intern(addressFirst ? "aAddress" : "bAddress"),
            params: [], returnType: types.unitType,
            body: [addressInstruction, .returnUnit],
            isSuspend: false, isInline: false
        )
        let callFunction = KIRFunction(
            symbol: SymbolID(rawValue: 1905),
            name: interner.intern(addressFirst ? "bCall" : "aCall"),
            params: [], returnType: types.unitType,
            body: [.constValue(result: handle, value: .intLiteral(0)), callInstruction, .returnUnit],
            isSuspend: false, isInline: false
        )
        let declarations = [addressFunction, callFunction].map { arena.appendDecl(.function($0)) }
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: declarations)], arena: arena
        )
        let backend = try LLVMBackend(
            target: TargetTriple.hostDefault(), optLevel: .O0, debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("flat-string-declaration-\(UUID().uuidString).ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }
        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        let runtimeDeclarations = ir.split(separator: "\n").filter {
            $0.hasPrefix("declare ") && $0.contains("@\(calleeName)(")
        }
        try #require(runtimeDeclarations.count == 1)
        // LLVM 14 uses typed pointers; newer LLVM uses opaque pointers and can
        // accept a mismatched call type, so object emission alone is insufficient.
        #expect(
            runtimeDeclarations[0].contains("declare ptr @\(calleeName)(i64, ptr, ptr, ptr)")
                || runtimeDeclarations[0].contains("declare i8* @\(calleeName)(i64, i64*, i64*, i64*)")
        )
        #expect(ir.contains("call ptr @\(calleeName)(") || ir.contains("call i8* @\(calleeName)("))
    }
}
#endif
