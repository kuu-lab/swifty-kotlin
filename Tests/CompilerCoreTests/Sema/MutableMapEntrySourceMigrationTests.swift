#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

/// MutableEntry's source member contract must dispatch to custom implementations
/// as well as runtime-backed entries, including through imported stdlib metadata.
@Suite
struct MutableMapEntrySourceMigrationTests {
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

    @Test(arguments: [false, true])
    func setValueResolvesToBundledAbstractMemberAndDispatchesVirtually(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource(
            """
            class CustomEntry(override val key: String, initial: Int) : MutableMap.MutableEntry<String, Int> {
                override val value: Int get() = stored
                private var stored: Int = initial
                override fun setValue(newValue: Int): Int {
                    val old = stored
                    stored = newValue
                    return old
                }
            }
            fun custom(entry: MutableMap.MutableEntry<String, Int>): Int = entry.setValue(4)
            fun update(values: MutableMap<String, Int>): Int {
                val entry = values.iterator().next()
                return entry.setValue(42)
            }
            """,
            emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        try runToKIR(ctx)

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
        let memberFQName = mutableEntryFQName + [setValueName]
        let member = try #require(sema.symbols.lookup(fqName: memberFQName))
        let memberInfo = try #require(sema.symbols.symbol(member))
        #expect(sema.symbols.isSourceBackedSymbol(member))
        #expect(!memberInfo.flags.contains(.synthetic))
        #expect(memberInfo.flags.contains(.abstractType))
        #expect(memberInfo.flags.contains(.importedLibrary) == useArtifact)
        #expect(sema.symbols.parentSymbol(for: member) == mutableEntrySymbol)
        if !useArtifact {
            #expect(sema.symbols.externalLinkName(for: member) == nil)
            let fileID = try #require(sema.symbols.sourceFileID(for: member))
            #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/MutableMap.kt")
        }

        let signature = try #require(sema.symbols.functionSignature(for: member))
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.typeParameterSymbols.count == 2)
        #expect(signature.classTypeParameterCount == 2)
        #expect(signature.parameterTypes.first == signature.returnType)
        #expect(sema.symbols.nominalLayout(for: mutableEntrySymbol)?.vtableSlots[member] == 0)

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
        #expect(callIDs.count == 2)
        for callID in callIDs {
            #expect(sema.bindings.callBinding(for: callID)?.chosenCallee == member)
            #expect(sema.bindings.exprType(for: callID) == sema.types.intType)
        }
        let module = try #require(ctx.kir)
        for name in ["custom", "update"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: interner)
            #expect(extractVirtualCallees(from: body, interner: interner).contains("setValue"))
            #expect(!extractCallees(from: body, interner: interner).contains("__kk_mutable_map_entry_setValue"))
        }
    }
}
#endif
