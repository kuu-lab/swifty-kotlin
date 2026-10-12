import Foundation

// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Whether `receiverType`'s nominal owner is one of the atomic stdlib classes
    /// whose bundled `*At`/alias source is the live implementation. Gates the
    /// importless bundled-extension member fallback so it never surfaces the
    /// dead-mirror bundled sources of other stdlib families.
    func isAtomicMigrationReceiver(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let nonNull = sema.types.makeNonNullable(receiverType)
        guard let owner = driver.helpers.nominalSymbol(of: nonNull, types: sema.types),
              let symbol = sema.symbols.symbol(owner)
        else {
            return false
        }
        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        switch fqName {
        case "kotlin.concurrent.atomics.AtomicInt",
             "kotlin.concurrent.atomics.AtomicLong",
             "kotlin.concurrent.atomics.AtomicBoolean",
             "kotlin.concurrent.atomics.AtomicReference",
             "kotlin.concurrent.atomics.AtomicNativePtr",
             "kotlin.concurrent.atomics.AtomicIntArray",
             "kotlin.concurrent.atomics.AtomicLongArray",
             "kotlin.concurrent.AtomicInt",
             "kotlin.concurrent.AtomicLong",
             "kotlin.concurrent.AtomicBoolean",
             "kotlin.concurrent.AtomicReference",
             "kotlin.concurrent.AtomicIntArray",
             "kotlin.concurrent.AtomicLongArray",
             "java.util.concurrent.atomic.AtomicInteger":
            return true
        default:
            return false
        }
    }

    /// Finds the source-backed value-semantics extensions for Instant. Instant
    /// keeps these operations as package-level Kotlin functions, but its source
    /// nominal shell also inherits Any's methods. They must be preferred when
    /// the call site's static receiver is Instant.
    func collectInstantValueSemanticsCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let knownNames = KnownCompilerNames(interner: interner)
        guard knownNames.instantValueSemanticsMemberNames.contains(calleeName),
              let receiverOwner = driver.helpers.nominalSymbol(
                  of: sema.types.makeNonNullable(receiverType),
                  types: sema.types
              ),
              let receiverSymbol = sema.symbols.symbol(receiverOwner),
              receiverSymbol.fqName == knownNames.kotlinTimeInstantFQName
        else {
            return []
        }

        let kotlinTimePackage = knownNames.kotlinTimePackage
        return sema.symbols.lookupByShortName(calleeName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  Array(symbol.fqName.dropLast()) == kotlinTimePackage,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }
    }

    /// Finds bundled stdlib extension functions named `calleeName` whose receiver
    /// matches `receiverType`. Bundled stdlib extensions (e.g. the atomic-array
    /// `loadAt`/`storeAt` migration source) are conceptually members and should be
    /// callable without an explicit import, but ordinary scope lookup only exposes
    /// them when imported. This is used as a final member-call resolution fallback,
    /// so it only affects calls that would otherwise be unresolved. Membership is
    /// gated by `sema.bundledIndex` so user-declared extensions are never surfaced
    /// here without import.
    func collectBundledStdlibExtensionCandidates(
        named calleeName: InternedString,
        receiverType: TypeID,
        requireOperator: Bool = false,
        sourceFile: ASTFile? = nil,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        // This importless-member fallback exists only for the atomic stdlib
        // migration (KSP-672 and the scalar alias mirror): those bundled sources
        // are the live implementation and their synthetic stubs are intentionally
        // skipped. Other bundled stdlib sources (collection/sequence/text HOFs)
        // are dead mirrors whose canonical lowering goes through runtime helpers,
        // so surfacing them here would wrongly pre-empt that path.
        guard isAtomicMigrationReceiver(receiverType, sema: sema, interner: interner) else {
            return []
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        let candidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }
            // Source-backed bundled stdlib extensions are not synthetic; imported
            // stdlib artifact symbols are synthetic + importedLibrary and should
            // still be considered here so shared-path code can resolve them.
            if symbol.flags.contains(.synthetic), !symbol.flags.contains(.importedLibrary) {
                return false
            }
            if requireOperator, !symbol.flags.contains(.operatorFunction) {
                return false
            }
            // Property accessor functions share the short names get/set; their
            // parent is a property symbol and must not pollute member lookup.
            if let parentID = sema.symbols.parentSymbol(for: candidate),
               let parentSym = sema.symbols.symbol(parentID),
               parentSym.kind == .property
            {
                return false
            }
            guard let key = BundledDeclarationIndex.memberKey(
                for: symbol,
                symbolID: candidate,
                symbols: sema.symbols,
                types: sema.types,
                interner: interner
            )
            else {
                return false
            }
            // Typealias receivers expand to their runtime nominal owner when a
            // symbol key is built. The AST index still retains the declaration's
            // package for source-backed aliases, so accept either representation
            // here and let the source-file provenance filter choose between them.
            let declaredOwnerKey = BundledMemberKey(
                ownerFQName: Array(symbol.fqName.dropLast()),
                name: symbol.name,
                arity: signature.parameterTypes.count
            )
            guard sema.bundledIndex.contains(key)
                || sema.bundledIndex.contains(declaredOwnerKey)
            else {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiver,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }
        guard !candidates.isEmpty else {
            return []
        }

        // Typealiases for the canonical and legacy atomic packages expand to the
        // same runtime nominal type. When both source implementations are in the
        // symbol table, retain the package selected by the current file's import
        // or package context instead of reporting a false opt-in/overload clash.
        guard let sourceFile,
              let preferredPackage = preferredBundledStdlibPackage(
                  sourceFile: sourceFile,
                  candidates: candidates,
                  receiverType: nonNullReceiver,
                  sema: sema
              )
        else {
            return candidates
        }
        let preferredCandidates = candidates.filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate) else {
                return false
            }
            return Array(symbol.fqName.dropLast()) == preferredPackage
        }
        return preferredCandidates.isEmpty ? candidates : preferredCandidates
    }

    /// Chooses the bundled source package that introduced the receiver visible
    /// at a call site. Canonical atomics aliases and their legacy shells share a
    /// runtime class, so the receiver type alone cannot carry this provenance.
    func preferredBundledStdlibPackage(
        sourceFile: ASTFile,
        candidates: [SymbolID],
        receiverType: TypeID,
        sema: SemaModule
    ) -> [InternedString]? {
        let packages = candidates.compactMap { candidate -> [InternedString]? in
            guard let symbol = sema.symbols.symbol(candidate), symbol.fqName.count > 1 else {
                return nil
            }
            return Array(symbol.fqName.dropLast())
        }
        guard !packages.isEmpty else {
            return nil
        }
        if packages.contains(where: { $0 == sourceFile.packageFQName }) {
            return sourceFile.packageFQName
        }

        let receiverOwner = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(receiverType),
            types: sema.types
        )
        for importDecl in sourceFile.imports {
            let path = importDecl.path
            if packages.contains(path) {
                return path
            }
            guard path.count > 1,
                  let package = packages.first(where: { $0 == Array(path.dropLast()) }),
                  let receiverOwner
            else {
                continue
            }
            let matchesReceiver = sema.symbols.lookupAll(fqName: path).contains { importedID in
                guard let imported = sema.symbols.symbol(importedID) else {
                    return false
                }
                let importedType: TypeID?
                switch imported.kind {
                case .class, .interface, .object, .enumClass, .annotationClass:
                    importedType = sema.types.make(.classType(ClassType(
                        classSymbol: importedID,
                        args: [],
                        nullability: .nonNull
                    )))
                case .typeAlias:
                    importedType = sema.symbols.typeAliasUnderlyingType(for: importedID)
                default:
                    importedType = nil
                }
                guard let importedType,
                      let importedOwner = driver.helpers.nominalSymbol(
                          of: sema.types.makeNonNullable(importedType),
                          types: sema.types
                      )
                else {
                    return false
                }
                return importedOwner == receiverOwner
            }
            if matchesReceiver {
                return package
            }
        }
        return nil
    }

}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
