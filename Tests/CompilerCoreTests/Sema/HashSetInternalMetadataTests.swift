@testable import CompilerCore
import RuntimeABI
import Testing
import TestStdlibCache

@Suite
struct HashSetInternalMetadataTests {
    @Test(arguments: [false, true])
    func internalMembersKeepTheirSourceAndArtifactContracts(useArtifact: Bool) throws {
        let ctx = try context("fun probe(set: HashSet<String?>): Boolean = set.isEmpty()", useArtifact: useArtifact)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ownerFQName = ["kotlin", "collections", "HashSet"].map(ctx.interner.intern)
        let owner = try #require(sema.symbols.lookup(fqName: ownerFQName))
        let element = try #require(sema.types.nominalTypeParameterSymbols(for: owner).first)

        for name in ["build", "getElement"] {
            let members = sema.symbols.lookupAll(fqName: ownerFQName + [ctx.interner.intern(name)])
            #expect(members.count == 1, "Expected a single HashSet.\(name) declaration")
            let member = try #require(members.first)
            let info = try #require(sema.symbols.symbol(member))
            #expect(info.kind == .function)
            #expect(info.flags.contains(.importedLibrary) == useArtifact)
            #expect(sema.symbols.parentSymbol(for: member) == owner)
            if useArtifact {
                let linkName = try #require(sema.symbols.externalLinkName(for: member))
                #expect(linkName.hasPrefix(RuntimeABISpec.compilerGeneratedLinkNamePrefix + "\(name)_"))
            } else {
                #expect(!info.flags.contains(.synthetic))
                #expect(sema.symbols.externalLinkName(for: member) == nil)
                #expect(sema.symbols.isSourceBackedSymbol(member))
                let file = try #require(sema.symbols.sourceFileID(for: member))
                #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/collections/HashSet.kt")
                #expect(info.declSite != nil)
            }

            let signature = try #require(sema.symbols.functionSignature(for: member))
            let annotations = sema.symbols.annotations(for: member)
            if name == "build" {
                #expect(info.visibility == .internal)
                #expect(signature.parameterTypes.isEmpty)
                #expect(annotations.contains { $0.annotationFQName == "PublishedApi" })
                let set = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "Set"].map(ctx.interner.intern)))
                guard case let .classType(result) = sema.types.kind(of: signature.returnType) else {
                    Issue.record("HashSet.build must return Set<E>")
                    continue
                }
                #expect(result.classSymbol == set)
                #expect(result.nullability == .nonNull)
                #expect(result.args == [.invariant(sema.types.make(.typeParam(TypeParamType(symbol: element, nullability: .nonNull))))])
            } else {
                #expect(info.visibility == .public)
                #expect(signature.parameterTypes == [sema.types.make(.typeParam(TypeParamType(symbol: element, nullability: .nonNull)))])
                #expect(signature.returnType == sema.types.make(.typeParam(TypeParamType(symbol: element, nullability: .nullable))))
                #expect(annotations.contains { $0.annotationFQName == "Deprecated" })
                let since = try #require(annotations.first { $0.annotationFQName == "DeprecatedSinceKotlin" })
                #expect(since.arguments.contains { $0.hasPrefix("warningSince=") && $0.contains("1.9") })
                #expect(since.arguments.contains { $0.hasPrefix("errorSince=") && $0.contains("2.1") })
            }
        }
    }

    @Test(arguments: [false, true])
    func getElementIsErrorDeprecatedForUserCode(useArtifact: Bool) throws {
        let ctx = try context("fun probe(set: HashSet<String>, element: String): String? = set.getElement(element)", useArtifact: useArtifact)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        let error = try #require(errors.first)
        #expect(error.code == "KSWIFTK-SEMA-DEPRECATED")
        #expect(error.message.contains("getElement"))
        #expect(error.message.contains("This function is not supposed to be used directly."))
    }

    @Test(arguments: [false, true])
    func publishedBuildRemainsInaccessibleToUserCode(useArtifact: Bool) throws {
        let ctx = try context("fun probe(set: HashSet<String>): Set<String> = set.build()", useArtifact: useArtifact)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        let error = try #require(errors.first)
        #expect(error.code == "KSWIFTK-SEMA-0044")
        #expect(error.message.contains("build"))
    }

    @Test
    func metadataRoundTripPreservesInternalVisibilityAndDeprecation() throws {
        let ctx = try context("fun probe() {}", useArtifact: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: sema.symbols,
            types: sema.types,
            moduleName: "KSwiftKStdlib",
            interner: ctx.interner,
            functionLinkNames: [:],
            includeNonPublic: true,
            includeSynthetic: false
        ).filter { ["kotlin.collections.HashSet.build", "kotlin.collections.HashSet.getElement"].contains($0.fqName) }
        #expect(records.count == 2)
        let decoded = MetadataDecoder().decode(encoder.serialize(records))
        #expect(decoded.count == 2)
        for original in records {
            let roundTripped = try #require(decoded.first { $0.fqName == original.fqName })
            #expect(roundTripped.visibility == original.visibility)
            #expect(roundTripped.typeSignature == original.typeSignature)
            #expect(roundTripped.annotations == original.annotations)
        }
    }

    private func context(_ source: String, useArtifact: Bool) throws -> CompilationContext {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource(
            source,
            emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        try runSema(ctx)
        return ctx
    }
}
