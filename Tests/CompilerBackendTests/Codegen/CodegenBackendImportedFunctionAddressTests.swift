#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendImportedFunctionAddressTests {
    @Test(arguments: ["__kk_pair_new", "__kk_mutable_map_put"])
    func runtimeFunctionAddressUsesKnownArityAndThrownChannel(linkName: String) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let address = KIRExprKind.externSymbolAddress(interner.intern(linkName))
        let addressExpr = arena.appendExpr(address, type: types.intType)
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 4000),
            name: interner.intern("address"),
            params: [],
            returnType: types.intType,
            body: [.constValue(result: addressExpr, value: address), .returnValue(addressExpr)],
            isSuspend: false,
            isInline: false
        )
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [arena.appendDecl(.function(function))])],
            arena: arena
        )
        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O2,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }
        try backend.emitLLVMIR(module: module, outputIRPath: irPath, interner: interner, typeSystem: types)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        let declaration = try #require(ir.split(separator: "\n").first {
            $0.hasPrefix("declare ") && $0.contains("@\(linkName)(")
        })
        if linkName == "__kk_pair_new" {
            #expect(declaration.contains("(i64, i64)"))
        } else {
            #expect(declaration.contains("(i64, i64, i64, i64*)")
                || declaration.contains("(i64, i64, i64, ptr)"))
        }
    }

    @Test(arguments: [false, true], [0, 2])
    func importedStringFunctionAddressMatchesCallABI(useSymbolRef: Bool, optimization: Int) throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let arena = KIRArena()
        let linkName = "kk_fn_imported_string"
        let importedSymbol = symbols.define(
            kind: .function,
            name: interner.intern("importedString"),
            fqName: [interner.intern("importedString")],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary]
        )
        symbols.setExternalLinkName(linkName, for: importedSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.stringType],
                returnType: types.stringType,
                valueParameterSymbols: []
            ),
            for: importedSymbol
        )

        let address: KIRExprKind = useSymbolRef
            ? .symbolRef(importedSymbol)
            : .externSymbolAddress(interner.intern(linkName))
        let addressExpr = arena.appendExpr(address, type: types.intType)
        let addressFunction = KIRFunction(
            symbol: SymbolID(rawValue: 4000),
            name: interner.intern("address"),
            params: [],
            returnType: types.intType,
            body: [.constValue(result: addressExpr, value: address), .returnValue(addressExpr)],
            isSuspend: false,
            isInline: false
        )
        let parameter = SymbolID(rawValue: 4001)
        let argument = arena.appendExpr(.symbolRef(parameter), type: types.stringType)
        let result = arena.appendExpr(.temporary(0), type: types.stringType)
        let caller = KIRFunction(
            symbol: SymbolID(rawValue: 4002),
            name: interner.intern("caller"),
            params: [KIRParameter(symbol: parameter, type: types.stringType)],
            returnType: types.stringType,
            body: [
                .call(
                    symbol: importedSymbol,
                    callee: interner.intern("importedString"),
                    arguments: [argument],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(result),
            ],
            isSuspend: false,
            isInline: false
        )
        let declarations = [addressFunction, caller].map { arena.appendDecl(.function($0)) }
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: declarations)],
            arena: arena
        )
        let backend = try LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }
        try backend.emitLLVMIR(
            module: module,
            outputIRPath: irPath,
            interner: interner,
            typeSystem: types,
            symbols: symbols
        )
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        let declaration = try #require(ir.split(separator: "\n").first {
            $0.hasPrefix("declare ") && $0.contains("@\(linkName)(")
        })
        #expect(declaration.filter { $0 == "{" }.count == 2, "String argument and return must both be aggregates")
        #expect(declaration.contains("i64*)") || declaration.contains(", ptr)"), "Missing thrown channel")
    }
}
#endif
