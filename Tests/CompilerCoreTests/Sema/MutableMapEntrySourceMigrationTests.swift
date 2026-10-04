#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

/// KSP-1076: MutableMap.MutableEntry.setValue is a bundled source extension
/// backed by the existing mutable-map entry runtime bridge.
@Suite
struct MutableMapEntrySourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/collections/MutableMap/MutableEntry/MutableEntry.kt"

    @Test(arguments: [false, true])
    func mutableEntryInterfaceIsOwnedByBundledSource(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: [
            """
            fun <K, V> readOnly(entry: MutableMap.MutableEntry<K, V>): Map.Entry<K, V> = entry
            fun key(entry: MutableMap.MutableEntry<String, Int>): String = entry.key
            fun value(entry: MutableMap.MutableEntry<String, Int>): Int = entry.value
            """,
        ]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let collections = ["kotlin", "collections"].map(ctx.interner.intern)
            let owner = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("MutableMap")]))
            let fqName = collections + [ctx.interner.intern("MutableMap"), ctx.interner.intern("MutableEntry")]
            let entry = try #require(sema.symbols.lookup(fqName: fqName))
            #expect(sema.symbols.lookupAll(fqName: fqName).count == 1)
            #expect(sema.symbols.symbol(entry)?.kind == .interface)
            #expect(sema.symbols.parentSymbol(for: entry) == owner)
            #expect(sema.types.nominalTypeParameterSymbols(for: entry).count == 2)
            #expect(sema.types.nominalTypeParameterVariances(for: entry) == [.invariant, .invariant])
            #expect(sema.symbols.isSourceBackedSymbol(entry))
            #expect(sema.symbols.symbol(entry)?.flags.contains(.importedLibrary) == useArtifact)
            #expect(sema.symbols.externalLinkName(for: entry) == nil)
            if !useArtifact {
                #expect(sema.symbols.symbol(entry)?.flags.contains(.synthetic) == false)
                let fileID = try #require(sema.symbols.sourceFileID(for: entry))
                #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/MutableMap.kt")
            }
            let readOnlyEntry = try #require(sema.symbols.lookup(
                fqName: collections + [ctx.interner.intern("Map"), ctx.interner.intern("Entry")]
            ))
            #expect(sema.symbols.directSupertypes(for: entry).contains(readOnlyEntry))
            let parameters = sema.types.nominalTypeParameterSymbols(for: entry)
            let arguments = sema.symbols.supertypeTypeArgs(for: entry, supertype: readOnlyEntry)
            #expect(arguments.count == parameters.count)
            for (argument, parameter) in zip(arguments, parameters) {
                let type: TypeID
                switch argument {
                case let .invariant(value), let .out(value): type = value
                default:
                    Issue.record("Expected MutableEntry's type parameter in Map.Entry supertype")
                    continue
                }
                #expect(type == sema.types.make(.typeParam(TypeParamType(symbol: parameter))))
            }
        }
    }

    @Test(arguments: ["Any, Int", "String, Any"])
    func mutableEntryRejectsWidenedTypeArguments(typeArguments: String) throws {
        let ctx = makeContextFromSource(
            """
            fun widen(entry: MutableMap.MutableEntry<String, Int>): MutableMap.MutableEntry<\(typeArguments)> = entry
            """
        )
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func setValueResolvesToBundledSourceExtension() throws {
        let ctx = makeContextFromSource(
            """
            fun update(values: MutableMap<String, Int>): Int {
                val entry = values.iterator().next()
                return entry.setValue(42)
            }
            """
        )
        try runSema(ctx)

        let diagnosticSummary = ctx.diagnostics.diagnostics.map { diagnostic -> String in
            guard let range = diagnostic.primaryRange else {
                return diagnostic.code + ": " + diagnostic.message
            }
            return [
                ctx.sourceManager.path(of: range.start.file),
                diagnostic.code,
                diagnostic.message,
            ].joined(separator: ": ")
        }.joined(separator: "\n")
        #expect(
            !ctx.diagnostics.hasError,
            Comment(
                rawValue: "Expected MutableMap.MutableEntry.setValue to type-check cleanly, got: "
                    + diagnosticSummary
            )
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let collections = ["kotlin", "collections"].map(interner.intern)
        let mutableEntryFQName = collections
            + [interner.intern("MutableMap"), interner.intern("MutableEntry")]
        let mutableEntrySymbol = try #require(sema.symbols.lookup(fqName: mutableEntryFQName))

        let setValueName = interner.intern("setValue")
        let extensionFQName = collections + [setValueName]
        let sourceSymbols = sema.symbols.lookupAll(fqName: extensionFQName).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID)
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == sourcePath
        }
        #expect(sourceSymbols.count == 1, "Expected one bundled MutableEntry.setValue extension")

        let extensionSymbol = try #require(sourceSymbols.first)
        let extensionInfo = try #require(sema.symbols.symbol(extensionSymbol))
        #expect(sema.symbols.isSourceBackedSymbol(extensionSymbol))
        #expect(!extensionInfo.flags.contains(.synthetic))
        #expect(extensionInfo.flags.contains(.inlineFunction))
        #expect(sema.symbols.externalLinkName(for: extensionSymbol) == nil)

        let signature = try #require(sema.symbols.functionSignature(for: extensionSymbol))
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.typeParameterSymbols.count == 2)
        #expect(signature.classTypeParameterCount == 0)
        #expect(signature.parameterTypes.first == signature.returnType)
        let receiverType = try #require(signature.receiverType)
        guard case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)) else {
            Issue.record("MutableEntry.setValue must have a MutableMap.MutableEntry receiver")
            return
        }
        #expect(receiverClass.classSymbol == mutableEntrySymbol)
        #expect(receiverClass.args.count == 2)

        let syntheticMemberFQName = mutableEntryFQName + [setValueName]
        #expect(
            sema.symbols.lookup(fqName: syntheticMemberFQName) == nil,
            "Expected the residual synthetic MutableEntry.setValue member to be skipped"
        )

        let ast = try #require(ctx.ast)
        let callIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(exprID),
                  !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                  case let .memberCall(_, callee, _, args, _) = ast.arena.expr(exprID),
                  ctx.interner.resolve(callee) == "setValue",
                  args.count == 1
            else {
                return nil
            }
            return exprID
        }
        #expect(callIDs.count == 1, "Expected one user MutableEntry.setValue call")
        let callID = try #require(callIDs.first)
        let chosenCallee = try #require(sema.bindings.callBinding(for: callID)?.chosenCallee)
        #expect(chosenCallee == extensionSymbol)
        #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        #expect(sema.bindings.exprType(for: callID) == sema.types.intType)
    }
}
#endif
