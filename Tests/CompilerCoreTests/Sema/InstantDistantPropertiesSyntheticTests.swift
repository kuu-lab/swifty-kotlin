#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct InstantDistantPropertiesSyntheticTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected Instant distant properties to resolve cleanly, got: \(diagnostics)")
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testInstantDistantExtensionPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let instantSymbol = try #require(sema.symbols.lookup(
            fqName: kotlinTime + [interner.intern("Instant")]
        ))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        for property in [
            (name: "isDistantPast", linkName: "kk_instant_is_distant_past"),
            (name: "isDistantFuture", linkName: "kk_instant_is_distant_future"),
        ] {
            let propertySymbol = try #require(
                sema.symbols.lookupAll(fqName: kotlinTime + [interner.intern(property.name)]).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .property
                        && sema.symbols.extensionPropertyReceiverType(for: symbolID) == instantType
                },
                "Expected kotlin.time.Instant.\(property.name) extension property"
            )
            let getterSymbol = try #require(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))

            #expect(sema.symbols.propertyType(for: propertySymbol) == boolType)
            #expect(sema.symbols.externalLinkName(for: propertySymbol) == property.linkName)
            #expect(sema.symbols.externalLinkName(for: getterSymbol) == property.linkName)
            #expect(sema.symbols.functionSignature(for: getterSymbol)?.receiverType == instantType)
            #expect(sema.symbols.functionSignature(for: getterSymbol)?.returnType == boolType)
        }
    }

    @Test func testInstantDistantPropertiesResolveInSource() throws {
        let source = """
        import kotlin.time.*

        fun flags(instant: Instant): Boolean {
            return instant.isDistantPast || instant.isDistantFuture
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let flagsSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("flags")]))
        let signature = try #require(sema.symbols.functionSignature(for: flagsSymbol))
        #expect(signature.returnType == sema.types.make(.primitive(.boolean, .nonNull)))
    }
}
#endif
