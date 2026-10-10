
struct TypeCheckScopeBuilder {
    func buildFileScopes(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) -> [Int32: FileScope] {
        var topLevelSymbolsByPackage = collectTopLevelSymbolsByPackage(ast: ast, sema: sema)
        let librarySymbolsByPackage = collectLibraryTopLevelSymbolsByPackage(sema: sema, interner: interner)
        for (packagePath, symbols) in librarySymbolsByPackage {
            topLevelSymbolsByPackage[packagePath, default: []].append(contentsOf: symbols)
        }
        let defaultImportPackages = makeDefaultImportPackages(interner: interner)
        // Default imports are identical for every file in this compilation.
        // Populate this shared parent once; file-specific bindings stay in
        // the child scopes and never mutate the default-import scope.
        let defaultImportScope = ImportScope(parent: nil, symbols: sema.symbols)
        for packagePath in defaultImportPackages {
            for importedSymbol in topLevelSymbolsByPackage[packagePath] ?? [] {
                if shouldSkipDefaultImport(importedSymbol, sema: sema, interner: interner) {
                    continue
                }
                defaultImportScope.insert(importedSymbol)
            }
        }
        var fileScopes: [Int32: FileScope] = [:]

        for file in ast.sortedFiles {
            let wildcardImportScope = ImportScope(parent: defaultImportScope, symbols: sema.symbols)
            let explicitImportScope = ExplicitImportScope(parent: wildcardImportScope, symbols: sema.symbols)
            populateImportScopes(
                for: file,
                sema: sema,
                explicitImportScope: explicitImportScope,
                wildcardImportScope: wildcardImportScope,
                topLevelSymbolsByPackage: topLevelSymbolsByPackage,
                diagnostics: sema.diagnostics,
                interner: interner,
                sourceManager: sourceManager
            )

            let packageScope = PackageScope(parent: explicitImportScope, symbols: sema.symbols)
            let fileScope = FileScope(parent: packageScope, symbols: sema.symbols)
            for packageSymbol in topLevelSymbolsByPackage[file.packageFQName] ?? [] {
                // KSP-1150: the coroutine registry retains a root-level
                // CancellationException compatibility class. An explicit
                // import of the source-backed class must take precedence over
                // that residual alias in the root package.
                if shouldSkipRootCancellationCompatibilityAlias(
                    packageSymbol,
                    file: file,
                    sema: sema,
                    interner: interner
                ) {
                    continue
                }
                if let symbol = sema.symbols.symbol(packageSymbol),
                   symbol.visibility == .private,
                   (sema.symbols.sourceFileID(for: packageSymbol) ?? symbol.declSite?.start.file) == file.fileID {
                    fileScope.insert(packageSymbol)
                } else {
                    packageScope.insert(packageSymbol)
                }
            }

            fileScopes[file.fileID.rawValue] = fileScope
        }

        return fileScopes
    }

    private func shouldSkipRootCancellationCompatibilityAlias(
        _ symbolID: SymbolID,
        file: ASTFile,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard file.packageFQName.isEmpty,
              let symbol = sema.symbols.symbol(symbolID),
              symbol.kind == .class,
              symbol.flags.contains(.synthetic),
              symbol.fqName.count == 1,
              symbol.name == interner.intern("CancellationException")
        else {
            return false
        }

        return file.imports.contains { importDecl in
            guard importDecl.alias == nil,
                  importDecl.isWildcard || importDecl.path.last == symbol.name
            else {
                return false
            }
            let importedPath = importDecl.isWildcard ? importDecl.path + [symbol.name] : importDecl.path
            return sema.symbols.lookupAll(fqName: importedPath).contains { importedID in
                guard let imported = sema.symbols.symbol(importedID) else {
                    return false
                }
                return (imported.kind == .class || imported.kind == .typeAlias)
                    && imported.fqName.count > 1
                    && importedID != symbolID
            }
        }
    }

    func collectTopLevelSymbolsByPackage(
        ast: ASTModule,
        sema: SemaModule
    ) -> [[InternedString]: [SymbolID]] {
        var mapping: [[InternedString]: [SymbolID]] = [:]
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }
                mapping[file.packageFQName, default: []].append(symbol)
            }
        }
        return mapping
    }

    private func resolveExplicitImport(_ path: [InternedString], sema: SemaModule) -> [SymbolID] {
        let resolved = sema.symbols.lookupAll(fqName: path)
        guard resolved.isEmpty, let name = path.last else { return resolved }
        // Bundled companion constants are package-owned extension properties.
        // Resolve the qualifier as a singleton and retain only its extensions,
        // rather than falling back to unrelated same-name package properties.
        let owners = Set(sema.symbols.lookupAll(fqName: Array(path.dropLast())).filter {
            sema.symbols.symbol($0)?.kind == .object
        })
        guard !owners.isEmpty else { return [] }
        var candidates: Set<SymbolID> = []
        for owner in owners {
            guard let ownerInfo = sema.symbols.symbol(owner) else { continue }
            // Imported metadata carries package parents; source nominal
            // anchors can omit them. Support both representations.
            var parent = sema.symbols.parentSymbol(for: owner)
            while let current = parent, let info = sema.symbols.symbol(current) {
                if info.kind == .package {
                    candidates.formUnion(sema.symbols.lookupAll(fqName: info.fqName + [name]))
                    break
                }
                parent = sema.symbols.parentSymbol(for: current)
            }
            for count in stride(from: ownerInfo.fqName.count - 1, through: 1, by: -1) {
                let package = Array(ownerInfo.fqName.prefix(count))
                if sema.symbols.lookupAll(fqName: package).contains(where: {
                    sema.symbols.symbol($0)?.kind == .package
                }) {
                    candidates.formUnion(sema.symbols.lookupAll(fqName: package + [name]))
                    break
                }
            }
        }
        return candidates.sorted { $0.rawValue < $1.rawValue }.filter { candidate in
            guard sema.symbols.symbol(candidate)?.kind == .property,
                  let receiver = sema.symbols.extensionPropertyReceiverType(for: candidate),
                  case let .classType(receiverClass) = sema.types.kind(of: receiver)
            else { return false }
            return owners.contains(receiverClass.classSymbol)
        }
    }

    func populateImportScopes(
        for file: ASTFile,
        sema: SemaModule,
        explicitImportScope: ImportScope,
        wildcardImportScope: ImportScope,
        topLevelSymbolsByPackage: [[InternedString]: [SymbolID]],
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) {
        var usedAliasNames: Set<InternedString> = []
        let suppressesInvisibleAccess = file.annotations.contains { annotation in
            KnownCompilerAnnotation.suppress.matches(annotation.name) && annotation.arguments.contains {
                let code = $0.filter { $0 != "\"" && $0 != "'" }
                return code == "INVISIBLE_MEMBER" || code == "INVISIBLE_REFERENCE"
            }
        }
        let visibility = VisibilityChecker(
            symbols: sema.symbols, sourceManager: sourceManager,
            invisibleAccessFiles: suppressesInvisibleAccess ? [file.fileID.rawValue] : []
        )
        func isAccessibleWildcardSymbol(_ id: SymbolID) -> Bool {
            guard let symbol = sema.symbols.symbol(id) else { return false }
            return visibility.isAccessible(symbol, fromFile: file.fileID, enclosingClass: nil)
        }

        for importDecl in file.imports {
            if let alias = importDecl.alias {
                if interner.resolve(alias).isEmpty {
                    continue
                }

                let resolved = resolveExplicitImport(importDecl.path, sema: sema)

                let isPackageOnlyImport = !resolved.isEmpty && resolved.allSatisfy {
                    sema.symbols.symbol($0)?.kind == .package
                }

                if isPackageOnlyImport {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0022",
                        "Cannot use alias on wildcard import.",
                        range: importDecl.range
                    )
                    continue
                }

                if resolved.isEmpty {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "Unresolved import path.",
                        range: importDecl.range
                    )
                    continue
                }

                if usedAliasNames.contains(alias) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0023",
                        "Import alias conflicts with a previous import alias in the same file.",
                        range: importDecl.range
                    )
                    continue
                }

                let importedSymbols = resolved.filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID) else {
                        return false
                    }
                    return symbol.kind != .package
                }

                for importedSymbol in importedSymbols {
                    explicitImportScope.insertWithAlias(importedSymbol, asName: alias)
                }

                usedAliasNames.insert(alias)
                continue
            }

            let resolved = importDecl.isWildcard
                ? sema.symbols.lookupAll(fqName: importDecl.path)
                : resolveExplicitImport(importDecl.path, sema: sema)
            if importDecl.isWildcard, resolved.contains(where: {
                sema.symbols.symbol($0)?.kind == .enumClass
            }) {
                // Enum entries belong to the enum, not a package. Source entries
                // are deliberately absent from the package-only symbol index.
                for entry in sema.symbols.children(ofFQName: importDecl.path)
                    where sema.symbols.symbol(entry)?.kind == .field && isAccessibleWildcardSymbol(entry) {
                    wildcardImportScope.insert(entry)
                }
            }
            if resolved.isEmpty {
                let packageSymbols = topLevelSymbolsByPackage[importDecl.path] ?? []
                if !packageSymbols.isEmpty {
                    for packageSymbol in packageSymbols {
                        if shouldSkipDefaultImport(packageSymbol, sema: sema, interner: interner) {
                            continue
                        }
                        if !isAccessibleWildcardSymbol(packageSymbol) { continue }
                        wildcardImportScope.insert(packageSymbol)
                    }
                }
                continue
            }

            let hasPackageImport = resolved.contains { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .package
            }
            let importedSymbols = resolved.filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind != .package
            }
            if !importedSymbols.isEmpty, !hasPackageImport {
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
                continue
            }
            if !importedSymbols.isEmpty, hasPackageImport {
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
            }

            // A non-wildcard import resolving to a declaration must not dump
            // that declaration's neighbours into the wildcard scope, even when
            // a synthetic package record shares its FQ name (KUU-1205).
            if sema.symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
                for importedSymbol in topLevelSymbolsByPackage[importDecl.path] ?? [] {
                    if shouldSkipDefaultImport(importedSymbol, sema: sema, interner: interner) {
                        continue
                    }
                    if !isAccessibleWildcardSymbol(importedSymbol) { continue }
                    wildcardImportScope.insert(importedSymbol)
                }
            }
        }
    }

    func collectLibraryTopLevelSymbolsByPackage(
        sema: SemaModule,
        interner: StringInterner
    ) -> [[InternedString]: [SymbolID]] {
        var knownPackages: Set<[InternedString]> = []
        for packageID in sema.symbols.symbols(ofKind: .package) {
            guard let packageSymbol = sema.symbols.symbol(packageID) else { continue }
            knownPackages.insert(packageSymbol.fqName)
        }

        var mapping: [[InternedString]: [SymbolID]] = [:]
        let allSymbols = sema.symbols.allSymbols()
        for symbol in allSymbols {
            guard symbol.kind != .package,
                  symbol.fqName.count >= 1
            else {
                continue
            }
            // Library extension functions are intentionally included in the package
            // mapping so default/wildcard imports make them visible for member-style
            // call resolution. Direct calls still filter them by requiring no receiver.
            let candidatePackage: [InternedString] = if symbol.fqName.count == 1 {
                []
            } else {
                Array(symbol.fqName.dropLast())
            }
            if !candidatePackage.isEmpty,
               !knownPackages.contains(candidatePackage),
               !symbol.flags.contains(.synthetic)
            {
                continue
            }
            // STDLIB-SHARED-009: Keep synthetic operator extensions (e.g. String.get)
            // out of the library package mapping. Source-backed operator extensions
            // remain so they are visible to other bundled source in the same package.
            if isSyntheticOperatorExtensionToExclude(symbol.id, sema: sema, interner: interner) {
                continue
            }
            mapping[candidatePackage, default: []].append(symbol.id)
        }
        return mapping
    }

    /// Returns true for synthetic operator extension functions that must not be
    /// entered into package/default-import scope mappings. These would shadow
    /// source-backed member implementations in implicit-receiver calls.
    /// Member-style and operator syntax still resolve them through CallTypeChecker
    /// fallback paths.
    private func isSyntheticOperatorExtensionToExclude(
        _ symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.kind == .function,
              let signature = sema.symbols.functionSignature(for: symbolID),
              signature.receiverType != nil,
              symbol.flags.contains(.operatorFunction),
              symbol.flags.contains(.synthetic),
              !sema.symbols.isSourceBackedSymbol(symbolID)
        else {
            return false
        }

        // STDLIB-SHARED-009: Keep synthetic operator extensions (e.g. String.get)
        // out of scope mappings. They are reachable through
        // CallTypeChecker fallback paths when needed.
        return true
    }

    /// Returns true for symbols that should not be inserted into the
    /// default-import or wildcard-import scopes. This includes the synthetic
    /// operator extensions covered by STDLIB-SHARED-009. Member-style and
    /// operator syntax (e.g. `cs[0]`) resolve source-backed interface members
    /// normally.
    private func shouldSkipDefaultImport(
        _ symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        if isSyntheticOperatorExtensionToExclude(symbolID, sema: sema, interner: interner) {
            return true
        }

        return false
    }

    func makeDefaultImportPackages(interner: StringInterner) -> [[InternedString]] {
        let packages: [[String]] = [
            ["kotlin"],
            ["kotlin", "annotation"],
            ["kotlin", "collections"],
            ["kotlin", "comparisons"],
            ["kotlin", "coroutines"],
            ["kotlin", "enums"],
            // kotlin.math is not a Kotlin default import; importing it here broke
            // member resolution for java.security.Signature.sign vs kotlin.math.sign.
            ["kotlin", "io"],
            ["kotlin", "jvm"],
            ["kotlin", "ranges"],
            ["kotlin", "reflect"],
            ["kotlin", "sequences"],
            ["kotlin", "text"],
            ["kotlin", "time"],
            ["kotlin", "system"],
            ["java", "lang"],
        ]
        return packages.map { segments in
            segments.map { interner.intern($0) }
        }
    }
}
