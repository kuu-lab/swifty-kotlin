@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SuspendFunctionSyntheticStubTests {

    @Test
    func testSuspendFunctionSyntheticStubTestsInventory() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testSuspendFunctionMarkerInterfaceIsRegistered ===
            do {

                let fqName = ["kotlin", "coroutines", "SuspendFunction"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.coroutines.SuspendFunction to be registered"
                )
                #expect(sema.symbols.symbol(symbol)?.kind == .interface)
                #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == true)

                let typeParameters = sema.types.nominalTypeParameterSymbols(for: symbol)
                #expect(typeParameters.count == 1)
                #expect(sema.types.nominalTypeParameterVariances(for: symbol) == [.out])

                let propertyType = try #require(sema.symbols.propertyType(for: symbol))
                guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
                    Issue.record("Expected SuspendFunction property type to be a class type")
                    return
                }
                #expect(classType.classSymbol == symbol)
                #expect(classType.args.count == 1)
                guard case let .out(returnType) = classType.args[0],
                      case let .typeParam(typeParam) = sema.types.kind(of: returnType)
                else {
                    Issue.record("Expected SuspendFunction<R> to expose covariant R")
                    return
                }
                #expect(typeParam.symbol == typeParameters[0])
            }
        }
    }

}
