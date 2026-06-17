@testable import CompilerCore
import XCTest

final class SetHOFKotlinSourceMigrationTests: XCTestCase {
    func testBundledSetHOFExtensionsAreRegisteredAsKotlinSource() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let setSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlin", "collections", "Set"].map { interner.intern($0) })
            )

            let members = [
                "filter",
                "map",
                "flatMap",
                "forEach",
                "sorted",
                "first",
                "last",
                "count",
                "any",
                "all",
                "none",
            ]

            for member in members {
                let fqName = ["kotlin", "collections", member].map { interner.intern($0) }
                let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(receiverClass) = sema.types.kind(of: receiverType)
                    else {
                        return false
                    }
                    return receiverClass.classSymbol == setSymbol
                }

                XCTAssertFalse(
                    sourceSymbols.isEmpty,
                    "Expected bundled Kotlin-source Set.\(member) extension to be registered"
                )
                XCTAssertTrue(
                    sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                    "Bundled Kotlin-source Set.\(member) extensions must not carry C external links"
                )
            }
        }
    }
}
