#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendDwarfAndInstructionLocationTrackingTests {

    @Test
    func testLLVMBackendDebugObjectContainsDwarfSections() throws {
        let bindings = try #require(LLVMCAPIBindings.loadUsable())
        #expect(bindings.debugInfoAvailable)

        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 4200)
        let expr0 = arena.appendExpr(.intLiteral(0))
        let function = KIRFunction(
            symbol: mainSym, name: interner.intern("main"), params: [],
            returnType: types.unitType,
            body: [.constValue(result: expr0, value: .intLiteral(0)), .returnValue(expr0)],
            isSuspend: false, isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])], arena: arena
        )

        let backendDebug = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: true,
            diagnostics: diagnostics
        )
        let backendNoDebug = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: diagnostics
        )

        let debugObjPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_debug.o").path
        let noDebugObjPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_nodebug.o").path
        defer {
            try? FileManager.default.removeItem(atPath: debugObjPath)
            try? FileManager.default.removeItem(atPath: noDebugObjPath)
        }

        try backendDebug.emitObject(
            module: module,
            outputObjectPath: debugObjPath, interner: interner
        )
        try backendNoDebug.emitObject(
            module: module,
            outputObjectPath: noDebugObjPath, interner: interner
        )

        let debugData = try Data(contentsOf: URL(fileURLWithPath: debugObjPath))
        let noDebugData = try Data(contentsOf: URL(fileURLWithPath: noDebugObjPath))

        #expect(debugData.count > 0)
        #expect(noDebugData.count > 0)
        #expect(
            debugData.count > noDebugData.count,
            "Debug object should be larger due to DWARF sections"
        )
    }

    @Test
    func testInstructionLocationsPreservedThroughTransformFunctions() {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let sym = SymbolID(rawValue: 4300)
        let expr0 = arena.appendExpr(.intLiteral(1))
        _ = arena.appendExpr(.intLiteral(2))

        let sourceRange = SourceRange(
            start: SourceLocation(file: FileID(rawValue: 0), offset: 10),
            end: SourceLocation(file: FileID(rawValue: 0), offset: 20)
        )

        let function = KIRFunction(
            symbol: sym, name: interner.intern("test"), params: [],
            returnType: types.unitType,
            body: [.constValue(result: expr0, value: .intLiteral(1)), .returnValue(expr0)],
            isSuspend: false, isInline: false,
            instructionLocations: [sourceRange, sourceRange]
        )
        _ = arena.appendDecl(.function(function))

        arena.transformFunctions { func0 in
            var updated = func0
            updated.instructionLocations = [nil, nil]
            return updated
        }

        if case let .function(transformed)? = arena.decl(KIRDeclID(rawValue: 0)) {
            #expect(transformed.instructionLocations.count == 2)
            #expect(transformed.instructionLocations[0] == nil)
            #expect(transformed.instructionLocations[1] == nil)
        } else {
            Issue.record("Expected function declaration")
        }
    }
}
#endif
