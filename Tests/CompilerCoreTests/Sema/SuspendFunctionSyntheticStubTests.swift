@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SuspendFunctionSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testSuspendFunctionMarkerInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

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
