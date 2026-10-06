#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-950: the complete build-family surface is owned by CollectionBuilders.kt.
/// The public overloads and their @PublishedApi internal counterparts must not
/// be replaced by residual synthetic declarations.
@Suite
struct CollectionBuildersKSP950Tests {
    // KUU-1249: Map's key is invariant; buildMap must retain K rather than
    // returning a projected key that cannot satisfy a forwarding declaration.
    @Test(arguments: ["action", "4, action"])
    func genericBuildMapForwardingPreservesKeyType(arguments: String) throws {
        let ctx = makeContextFromSource("""
        fun <T> gather(action: MutableMap<String, T>.() -> Unit): Map<String, T> = buildMap<String, T>(\(arguments))
        fun <K, V> gatherBoth(action: MutableMap<K, V>.() -> Unit): Map<K, V> = buildMap<K, V>(\(arguments))
        fun concrete(action: MutableMap<String, Int>.() -> Unit): Map<String, Int> = buildMap<String, Int>(\(arguments))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            .map { "\($0.code): \($0.message)" }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func buildMapDoesNotWidenInvariantKey() throws {
        let ctx = makeContextFromSource("""
        fun invalid(action: MutableMap<String, Int>.() -> Unit): Map<Any, Int> = buildMap<String, Int>(action)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test
    func buildFamilyHasSourceBackedPublicAndInternalOverloads() throws {
        let ctx = makeContextFromSource("fun useBuilders() = buildList { add(1) }")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)
        let sourcePath = "__bundled_kotlin/collections/CollectionBuilders.kt"
        let expected: [(name: String, visibility: Visibility)] = [
            ("buildList", .public),
            ("buildSet", .public),
            ("buildMap", .public),
            ("buildListInternal", .internal),
            ("buildSetInternal", .internal),
            ("buildMapInternal", .internal),
        ]

        for item in expected {
            let sourceSymbols = sema.symbols.lookupAll(
                fqName: packageFQName + [ctx.interner.intern(item.name)]
            ).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == sourcePath
            }

            #expect(sourceSymbols.count == 2, "Expected two (item.name) overloads")
            #expect(sourceSymbols.allSatisfy { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.visibility == item.visibility
                    && !symbol.flags.contains(.synthetic)
                    && sema.symbols.isSourceBackedSymbol(symbolID)
                    && sema.symbols.externalLinkName(for: symbolID) == nil
            })
            #expect(sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0) != nil })
            if item.name == "buildMap" || item.name == "buildMapInternal" {
                for symbolID in sourceSymbols {
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    guard case let .classType(result) = sema.types.kind(of: signature.returnType) else {
                        Issue.record("Expected a Map return type")
                        continue
                    }
                    #expect(result.args.count == 2)
                    for (argument, parameter) in zip(result.args, signature.typeParameterSymbols) {
                        guard case let .invariant(type) = argument,
                              case let .typeParam(typeParameter) = sema.types.kind(of: type) else {
                            Issue.record("buildMap must return Map<K, V> without use-site projections")
                            continue
                        }
                        #expect(typeParameter.symbol == parameter)
                    }
                }
            }
        }
    }
}
#endif
