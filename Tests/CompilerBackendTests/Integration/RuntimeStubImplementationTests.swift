#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct RuntimeStubImplementationTests {
    private func makeSimpleModule(interner: StringInterner) -> KIRModule {
        let arena = KIRArena()
        let main = KIRFunction(
            symbol: SymbolID(rawValue: 100),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let mainID = arena.appendDecl(.function(main))
        return KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )
    }

    @Test func testLLVMBackendDoesNotEmitFrameRuntimeCalls() throws {
        let interner = StringInterner()
        let module = makeSimpleModule(interner: interner)

        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)

        // ARCH-014: root-empty frame map registration / push / pop are no longer
        // emitted; the symbols must not appear in the IR at all.
        #expect(!ir.contains("kk_register_frame_map"), "LLVM IR must not reference kk_register_frame_map")
        #expect(!ir.contains("kk_push_frame"), "LLVM IR must not reference kk_push_frame")
        #expect(!ir.contains("kk_pop_frame"), "LLVM IR must not reference kk_pop_frame")
    }
}
#endif
