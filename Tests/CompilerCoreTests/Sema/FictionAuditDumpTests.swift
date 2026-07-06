#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FictionAuditDumpTests {
    @Test func dumpSyntheticSurfaceWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["DUMP_SURFACE"] == "1" else {
            return
        }

        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let allSymbols = sema.symbols.allSymbols()
            let syntheticSymbols = allSymbols.filter {
                $0.flags.contains(.synthetic)
            }
            let syntheticRootCounts = Dictionary(grouping: syntheticSymbols) { symbol -> String in
                guard let root = symbol.fqName.first else { return "<root>" }
                return ctx.interner.resolve(root)
            }.mapValues(\.count)

            print("FICTION_AUDIT_ALL_TOTAL=\(allSymbols.count)")
            print("FICTION_AUDIT_SYNTHETIC_TOTAL=\(syntheticSymbols.count)")
            for key in syntheticRootCounts.keys.sorted() {
                print("FICTION_AUDIT_SYNTHETIC_ROOT \(key)=\(syntheticRootCounts[key] ?? 0)")
            }
        }
    }
}
#endif
