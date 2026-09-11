@testable import CompilerCore
import Testing

/// KSP-941: the Map nominal declaration is source-backed (now via
/// `collections/Map/Map.kt`, landed independently by KSP-1067 #6627). These
/// tests pin the variance/type-parameter mechanics that KSP-941 introduced;
/// see `MapAsSourceMigrationTests` for member-level (get/size/keys/...)
/// coverage of the KSP-1067 declaration itself.
@Suite
struct MapInterfaceSourceMigrationTests {
    @Test
    func mapInterfaceUsesSourceDeclarationWithTargetVariance() throws {
        let ctx = makeContextFromSource(
            """
            fun probe(values: Map<String, Int>): Map<String, Int> = values
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let mapFQName = ["kotlin", "collections", "Map"].map(interner.intern)
        let mapSymbol = try #require(sema.symbols.lookup(fqName: mapFQName))
        let mapInfo = try #require(sema.symbols.symbol(mapSymbol))
        #expect(mapInfo.kind == .interface)
        #expect(!mapInfo.flags.contains(.synthetic))
        let mapSourceFile = try #require(sema.symbols.sourceFileID(for: mapSymbol))
        #expect(ctx.sourceManager.path(of: mapSourceFile) == "__bundled_kotlin/collections/Map/Map.kt")
        #expect(sema.types.nominalTypeParameterVariances(for: mapSymbol) == [.invariant, .out])

        let typeParameters = sema.types.nominalTypeParameterSymbols(for: mapSymbol)
        #expect(typeParameters.count == 2)
        #expect(sema.symbols.symbol(typeParameters[0])?.name == interner.intern("K"))
        #expect(sema.symbols.symbol(typeParameters[1])?.name == interner.intern("V"))
        let keyType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameters[0], nullability: .nonNull
        )))
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameters[1], nullability: .nonNull
        )))

        let getSymbol = try #require(sema.symbols.lookup(
            fqName: mapFQName + [interner.intern("get")]
        ))
        let getSignature = try #require(sema.symbols.functionSignature(for: getSymbol))
        let receiver = try #require(getSignature.receiverType)
        guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
            Issue.record("Map.get receiver should be a Map class type")
            return
        }
        #expect(receiverClass.classSymbol == mapSymbol)
        #expect(receiverClass.args.count == 2)
        #expect(receiverClass.args[0] == .invariant(keyType))
        #expect(receiverClass.args[1] == .out(valueType))
        #expect(getSignature.typeParameterSymbols == typeParameters)
        #expect(sema.symbols.externalLinkName(for: getSymbol) == "__kk_map_get")
    }

    @Test
    func mapInterfacePreservesKeyInvarianceAndValueCovariance() throws {
        let ctx = makeContextFromSource(
            """
            fun widen(values: Map<String, Int>): Map<String, Number> = values
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let mapSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "collections", "Map"].map(interner.intern)
        ))
        let stringInt = sema.types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(sema.types.stringType), .out(sema.types.intType)],
            nullability: .nonNull
        )))
        let stringAny = sema.types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(sema.types.stringType), .out(sema.types.anyType)],
            nullability: .nonNull
        )))
        let anyInt = sema.types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(sema.types.anyType), .out(sema.types.intType)],
            nullability: .nonNull
        )))
        #expect(sema.types.isSubtype(stringInt, stringAny))
        #expect(!sema.types.isSubtype(anyInt, stringInt))
    }
}
