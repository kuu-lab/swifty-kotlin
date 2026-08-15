#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct StdlibGapAuditDumpTests {
    @Test func dumpPublicSurfaceWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["GAP_AUDIT"] == "1" else {
            return
        }

        let outputPath = ProcessInfo.processInfo.environment["GAP_AUDIT_OUT"]
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("kswiftk_surface.tsv")
                .path

        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)

            var lines: [String] = []
            let symbols = sema.symbols.allSymbols().filter { $0.visibility == .public }

            for symbol in symbols.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
                let name = ctx.interner.resolve(symbol.name)
                let fqName = symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
                let flags = symbol.flags.isEmpty ? "" : "0x\(String(symbol.flags.rawValue, radix: 16))"

                var signature = ""
                switch symbol.kind {
                case .function, .constructor:
                    if let sig = sema.symbols.functionSignature(for: symbol.id) {
                        signature = Self.renderFunctionSignature(sig, types: sema.types, symbols: sema.symbols, interner: ctx.interner)
                    }
                case .property, .field, .backingField:
                    if let typeID = sema.symbols.propertyType(for: symbol.id) {
                        signature = "type=\(sema.types.displayName(of: typeID, symbols: sema.symbols, interner: ctx.interner))"
                    }
                case .typeAlias:
                    // Underlying type is not exposed publicly from SymbolTable.
                    break
                default:
                    break
                }

                let parts = [
                    "\(symbol.kind)",
                    fqName.isEmpty ? "<root>" : fqName,
                    name,
                    "\(symbol.visibility)",
                    flags,
                    signature
                ]
                lines.append(parts.joined(separator: "\t"))
            }

            let content = lines.joined(separator: "\n")
            try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("GAP_AUDIT_WRITTEN=\(outputPath)")
            print("GAP_AUDIT_PUBLIC_TOTAL=\(symbols.count)")
        }
    }

    private static func renderFunctionSignature(
        _ signature: FunctionSignature,
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        var parts: [String] = []

        if signature.isSuspend {
            parts.append("suspend")
        }

        if let receiver = signature.receiverType {
            let receiverDisplay = types.displayName(of: receiver, symbols: symbols, interner: interner)
            parts.append("receiver=\(receiverDisplay)")
        }

        let paramTypes = signature.parameterTypes
        let varargs = signature.valueParameterIsVararg
        let params = paramTypes.indices.map { index -> String in
            let type = types.displayName(of: paramTypes[index], symbols: symbols, interner: interner)
            if index < varargs.count && varargs[index] {
                return "vararg \(type)"
            }
            return type
        }.joined(separator: ", ")
        parts.append("params=(\(params))")

        let ret = types.displayName(of: signature.returnType, symbols: symbols, interner: interner)
        parts.append("return=\(ret)")

        if signature.canThrow {
            parts.append("throws")
        }

        return parts.joined(separator: " ")
    }
}
#endif
