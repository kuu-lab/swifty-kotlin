@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct GCShadowFrameCodegenTests {
    @Test(arguments: [0, 2])
    func weakReadPublishesItsResultAtomically(optimization: Int) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let parameter = SymbolID(rawValue: 51)
        let reference = arena.appendExpr(.symbolRef(parameter), type: types.anyType)
        let result = arena.appendTemporary(type: types.anyType)
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 52), name: interner.intern("readWeak"),
            params: [KIRParameter(symbol: parameter, type: types.anyType)], returnType: types.anyType,
            body: [
                .constValue(result: reference, value: .symbolRef(parameter)),
                .call(callee: interner.intern("kk_weak_ref_get"), arguments: [reference], result: result, canThrow: false),
                .returnValue(result),
            ],
            isSuspend: false, isInline: false
        )
        let declaration = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declaration])], arena: arena)
        let backend = try LLVMBackend(
            target: TargetTriple.hostDefault(), optLevel: optimization == 0 ? .O0 : .O2,
            debugInfo: false, diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-weak-commit-\(UUID().uuidString).ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }
        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        let read = try #require(ir.range(of: "call i64 @kk_weak_ref_get_rooted("))
        #expect(ir[read.upperBound...].contains("call i64 @kk_gc_shadow_set("))
        #expect(!ir.contains("call i64 @kk_weak_ref_get("))
    }

    @Test(arguments: [false, true])
    func importedGlobalUsesItsStorageKind(threadLocal: Bool) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let arena = KIRArena()
        let imported = symbols.define(
            kind: .property, name: interner.intern("imported"),
            fqName: [interner.intern("fixture"), interner.intern("imported")],
            declSite: nil, visibility: .public, flags: [.importedLibrary]
        )
        if threadLocal {
            symbols.setAnnotations([
                MetadataAnnotationRecord(annotationFQName: "kotlin.native.concurrent.ThreadLocal")
            ], for: imported)
        }
        let parameter = SymbolID(rawValue: 4001)
        let reference = arena.appendExpr(.symbolRef(parameter), type: types.anyType)
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 4002), name: interner.intern("storeImported"),
            params: [KIRParameter(symbol: parameter, type: types.anyType)], returnType: types.unitType,
            body: [.storeGlobal(value: reference, symbol: imported), .returnUnit],
            isSuspend: false, isInline: false
        )
        let declaration = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declaration])], arena: arena)
        let backend = try LLVMBackend(
            target: TargetTriple.hostDefault(), optLevel: .O0, debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-imported-global-\(UUID().uuidString).ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }
        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types, symbols: symbols)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        let expected = threadLocal ? "kk_gc_store_thread_local_global" : "kk_gc_store_global"
        #expect(ir.contains("call i64 @\(expected)("))
    }

    @Test(arguments: [0, 2])
    func storesStaticAndThreadLocalGlobalsAsRoots(optimization: Int) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let parameter = SymbolID(rawValue: 31)
        let staticGlobal = SymbolID(rawValue: 32)
        let threadLocal = SymbolID(rawValue: 33)
        let reference = arena.appendExpr(.symbolRef(parameter), type: types.anyType)
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 34), name: interner.intern("storeGlobals"),
            params: [KIRParameter(symbol: parameter, type: types.anyType)], returnType: types.unitType,
            body: [
                .constValue(result: reference, value: .symbolRef(parameter)),
                .storeGlobal(value: reference, symbol: staticGlobal),
                .storeGlobal(value: reference, symbol: threadLocal),
                .returnUnit,
            ],
            isSuspend: false, isInline: false
        )
        let declarations = [
            arena.appendDecl(.global(KIRGlobal(symbol: staticGlobal, type: types.anyType))),
            arena.appendDecl(.global(KIRGlobal(symbol: threadLocal, type: types.anyType, isThreadLocal: true))),
            arena.appendDecl(.function(function)),
        ]
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: declarations)], arena: arena)
        let backend = try LLVMBackend(
            target: TargetTriple.hostDefault(), optLevel: optimization == 0 ? .O0 : .O2,
            debugInfo: false, diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-globals-\(UUID().uuidString).ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }
        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        #expect(ir.components(separatedBy: "call i64 @kk_gc_store_global(").count - 1 == 1)
        #expect(ir.components(separatedBy: "call i64 @kk_gc_store_thread_local_global(").count - 1 == 1)
        #expect(ir.contains("thread_local"))
    }

    @Test(arguments: [0, 2])
    func emitsRootsAndBalancedReturnPaths(optimization: Int) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let parameter = SymbolID(rawValue: 21)
        let reference = arena.appendExpr(.symbolRef(parameter), type: types.anyType)
        let copied = arena.appendTemporary(type: types.anyType)
        let normal = KIRFunction(
            symbol: SymbolID(rawValue: 22), name: interner.intern("gcNormal"),
            params: [KIRParameter(symbol: parameter, type: types.anyType)], returnType: types.anyType,
            body: [
                .constValue(result: reference, value: .symbolRef(parameter)),
                .copy(from: reference, to: copied),
                .returnValue(copied),
            ],
            isSuspend: false, isInline: false
        )
        let exceptional = KIRFunction(
            symbol: SymbolID(rawValue: 23), name: interner.intern("gcExceptional"),
            params: [KIRParameter(symbol: parameter, type: types.anyType)], returnType: types.unitType,
            body: [
                .constValue(result: reference, value: .symbolRef(parameter)),
                .rethrow(value: reference),
            ],
            isSuspend: false, isInline: false
        )
        let declarations = [normal, exceptional].map { arena.appendDecl(.function($0)) }
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: declarations)], arena: arena)
        let backend = try LLVMBackend(
            target: TargetTriple.hostDefault(), optLevel: optimization == 0 ? .O0 : .O2, debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("gc-shadow-\(UUID().uuidString).ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }
        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        #expect(ir.components(separatedBy: "call i64 @kk_gc_shadow_push(").count - 1 == 2)
        #expect(ir.components(separatedBy: "call i64 @kk_gc_shadow_pop(").count - 1 == 2)
        #expect(ir.components(separatedBy: "call i64 @kk_gc_shadow_set(").count - 1 >= 4)
        #expect(ir.contains("declare i64 @kk_gc_shadow_push()"))
        #expect(ir.contains("declare i64 @kk_gc_shadow_set(i64, i64)"))
        #expect(ir.contains("declare i64 @kk_gc_shadow_pop(i64, i64)"))
    }
}
