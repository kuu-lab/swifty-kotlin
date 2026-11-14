
struct TypeCheckScopeBuilder {
    func buildFileScopes(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) -> [Int32: FileScope] {
        let topLevelSymbolsByPackage = collectTopLevelSymbolsByPackage(ast: ast, sema: sema)
        let defaultImportPackages = makeDefaultImportPackages(interner: interner)
        // Default imports are identical for every file in this compilation.
        // Populate this shared parent once; file-specific bindings stay in
        // the child scopes and never mutate the default-import scope.
        // Imported members resolve through `deferredCandidates`: the scope
        // asks the symbol table for `<package> + name`, which drains the
        // compact index for that name only instead of pre-collecting every
        // imported package member here.
        let defaultImportScope = DefaultImportScope(parent: nil, symbols: sema.symbols)
        let builtinClassifierFQNames = kotlinBuiltinClassifierFQNames(interner: interner)
        defaultImportScope.isKotlinBuiltinClassifier = { [sema] symbolID in
            guard let fqName = sema.symbols.symbol(symbolID)?.fqName else { return false }
            return builtinClassifierFQNames.contains(fqName)
        }
        for packagePath in defaultImportPackages {
            for importedSymbol in topLevelSymbolsByPackage[packagePath] ?? [] {
                if shouldSkipDefaultImport(importedSymbol, sema: sema)
                    || shouldSkipMappedJavaLangTypeDefaultImport(importedSymbol, sema: sema, interner: interner)
                    || isFilePrivateTopLevel(importedSymbol, sema: sema)
                {
                    continue
                }
                defaultImportScope.insert(importedSymbol)
            }
            defaultImportScope.addPackage(packagePath) { [self, sema] symbolID in
                !shouldSkipDefaultImport(symbolID, sema: sema)
                    && !shouldSkipMappedJavaLangTypeDefaultImport(symbolID, sema: sema, interner: interner)
                    && !isFilePrivateTopLevel(symbolID, sema: sema)
            }
        }
        var fileScopes: [Int32: FileScope] = [:]

        for file in ast.sortedFiles {
            let wildcardImportScope = WildcardImportScope(parent: defaultImportScope, symbols: sema.symbols)
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

            // Files suppressing invisible-access diagnostics keep the
            // unfiltered same-package candidates so the suppressed use site
            // still resolves (KUU-4232).
            let suppressesInvisibleAccess = file.annotations.contains { annotation in
                KnownCompilerAnnotation.suppress.matches(annotation.name)
                    && annotation.arguments.contains { argument in
                        let code = argument.filter { $0 != "\"" && $0 != "'" }
                        return code == "INVISIBLE_MEMBER" || code == "INVISIBLE_REFERENCE"
                    }
            }
            let checkInternalModuleVisibility = !suppressesInvisibleAccess

            let packageScope = PackageMembersScope(parent: explicitImportScope, symbols: sema.symbols)
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
                let packageSymbolInfo = sema.symbols.symbol(packageSymbol)
                if checkInternalModuleVisibility,
                   let packageSymbolInfo,
                   !isInternalVisibleFromFileModule(
                       packageSymbolInfo, file: file, sema: sema, sourceManager: sourceManager
                   )
                {
                    // Kotlin `internal` visibility is module-scoped: an
                    // internal declaration from the other module (bundled
                    // stdlib vs user sources) is not a same-package
                    // candidate and must not shadow a visible
                    // wildcard-imported alternative (KUU-4232).
                    continue
                }
                let isFilePrivate = packageSymbolInfo?.visibility == .private
                let declaredInThisFile = packageSymbolInfo != nil
                    && (sema.symbols.sourceFileID(for: packageSymbol)
                        ?? packageSymbolInfo?.declSite?.start.file) == file.fileID
                if isFilePrivate, declaredInThisFile {
                    fileScope.insert(packageSymbol)
                } else if let packageSymbolInfo,
                          !sema.symbols.isFilePrivateTopLevelVisible(packageSymbolInfo, fileID: file.fileID)
                {
                    // File-private top-level declarations are visible only
                    // inside their declaring file. Collecting one declared
                    // in another file would let the invisible candidate win
                    // over a visible alternative (e.g. a wildcard-imported
                    // enum entry) and then fail with SEMA-0040 at the use
                    // site (KUU-4312).
                    continue
                } else {
                    packageScope.insert(packageSymbol)
                }
            }
            packageScope.addPackage(file.packageFQName) { [self, sema, file, sourceManager, checkInternalModuleVisibility] symbolID in
                !shouldSkipRootCancellationCompatibilityAlias(
                    symbolID,
                    file: file,
                    sema: sema,
                    interner: interner
                ) && isPackageMemberVisibleFromFile(
                    symbolID, file: file, sema: sema, sourceManager: sourceManager,
                    checkInternalModuleVisibility: checkInternalModuleVisibility
                )
            }

            fileScopes[file.fileID.rawValue] = fileScope
        }

        return fileScopes
    }

    /// File-private top-level declarations never participate in default
    /// imports: they are visible only inside their declaring file, which
    /// reaches them through its own package scope instead (KUU-4312).
    private func isFilePrivateTopLevel(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        sema.symbols.symbol(symbolID)?.visibility == .private
    }

    /// Whether `symbolID` may be a same-package candidate for `file` through
    /// the deferred package-member path. File-private top-level declarations
    /// declared in another file are invisible here and must be skipped so a
    /// visible alternative can win (KUU-4312), as are `internal` declarations
    /// from the other module (KUU-4232).
    private func isPackageMemberVisibleFromFile(
        _ symbolID: SymbolID,
        file: ASTFile,
        sema: SemaModule,
        sourceManager: SourceManager?,
        checkInternalModuleVisibility: Bool
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else { return true }
        guard sema.symbols.isFilePrivateTopLevelVisible(symbol, fileID: file.fileID) else {
            return false
        }
        guard checkInternalModuleVisibility else { return true }
        return isInternalVisibleFromFileModule(
            symbol, file: file, sema: sema, sourceManager: sourceManager
        )
    }

    /// Whether `symbol` is visible to `file` under Kotlin's module-scoped
    /// `internal` rule. The bundled stdlib and user sources are separate
    /// modules, so an `internal` declaration is a resolution candidate only
    /// for files in the same module; without this filter an invisible
    /// same-package declaration wins its tier over a visible
    /// wildcard-imported alternative and the use site then fails with
    /// SEMA-0044 (KUU-4232). Internal declarations imported from a library
    /// artifact belong to that artifact's module and are never candidates
    /// here. Symbols whose declaring file or origin cannot be determined
    /// stay visible.
    private func isInternalVisibleFromFileModule(
        _ symbol: SemanticSymbol,
        file: ASTFile,
        sema: SemaModule,
        sourceManager: SourceManager?
    ) -> Bool {
        guard symbol.visibility == .internal else { return true }
        if symbol.flags.contains(.importedLibrary) { return false }
        guard let sourceManager else { return true }
        let fileIsBundledStdlib = sourceManager.origin(of: file.fileID)?.isBundledStdlib == true
        let declFileID = sema.symbols.sourceFileID(for: symbol.id) ?? symbol.declSite?.start.file
        guard let declFileID,
              let declOrigin = sourceManager.origin(of: declFileID)
        else { return true }
        return declOrigin.isBundledStdlib == fileIsBundledStdlib
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

    /// JDK classes that expose only static members are modelled as objects
    /// (for example `java.lang.Math`). On the JVM a star import such as
    /// `import java.lang.Math.*` contributes those static members, so the
    /// object's callable members are imported at wildcard priority instead
    /// of rejecting the import as an object star-import (KUU-4008).
    private func isJavaStaticFacade(_ symbol: SemanticSymbol, interner: StringInterner) -> Bool {
        guard symbol.kind == .object, let root = symbol.fqName.first else { return false }
        return root == interner.intern("java") || root == interner.intern("javax")
    }

    private func importJavaStaticFacadeMembers(
        _ owner: SymbolID,
        wildcardImportScope: PackageMembersScope,
        sema: SemaModule,
        isAccessibleWildcardSymbol: (SymbolID) -> Bool
    ) {
        for member in sema.symbols.declaredChildren(of: owner) {
            guard let memberSymbol = sema.symbols.symbol(member),
                  memberSymbol.kind == .function || memberSymbol.kind == .property,
                  isAccessibleWildcardSymbol(member)
            else { continue }
            wildcardImportScope.insert(member)
        }
    }

    /// Enum-class owners contributing entries to a wildcard `Owner.*` import.
    /// A source enum class shadows a same-FQN imported library enum —
    /// `SymbolTable.define` orders source declarations ahead of
    /// `.importedLibrary` ones (`prioritizeOverImported`) — so only the
    /// source enum's entries may be imported. Importing both enums'
    /// entries makes every shared entry name ambiguous (KSWIFTK-SEMA-0003).
    /// The shadowing declaration must be visible from the importing file:
    /// a file-private top-level enum in another file is not a package member
    /// there, so the imported enum keeps contributing its entries.
    private func enumOwnersForWildcardImport(
        _ resolved: [SymbolID],
        sema: SemaModule,
        isAccessibleSymbol: (SymbolID) -> Bool
    ) -> [SymbolID] {
        func isAccessibleOwner(_ id: SymbolID) -> Bool {
            var owner: SymbolID? = id
            while let current = owner {
                if !isAccessibleSymbol(current) { return false }
                owner = sema.symbols.parentSymbol(for: current)
            }
            return true
        }
        func isSourceOwner(_ id: SymbolID) -> Bool {
            sema.symbols.symbol(id)?.flags.contains(.importedLibrary) != true
        }
        let enumOwners = resolved.filter { sema.symbols.symbol($0)?.kind == .enumClass }
        let hasAccessibleSourceOwner = enumOwners.contains { id in
            isSourceOwner(id) && isAccessibleOwner(id)
        }
        guard hasAccessibleSourceOwner else { return enumOwners }
        return enumOwners.filter { id in
            isSourceOwner(id) && isAccessibleOwner(id)
        }
    }

    /// Under `--profile minimal`, an import into a package the minimal stdlib
    /// leaves out is reported as such (KUU-3016) rather than as a plain
    /// unresolved import, so the fix — drop `--profile minimal` — is explicit.
    ///
    /// The check is "not declared by the user", not "does not resolve": some
    /// excluded packages still have Swift-side synthetic stubs (for example
    /// `kotlinx.coroutines.runBlocking`) that resolve in Sema but have no
    /// implementation in a minimal artifact, so they would otherwise pass
    /// type checking and fail later as an undefined link symbol.
    ///
    /// Returns true when the import was reported and must not be processed
    /// further.
    private func reportMinimalProfileExcludedImport(
        _ importDecl: ImportDecl,
        topLevelSymbolsByPackage: [[InternedString]: [SymbolID]],
        sema: SemaModule,
        interner: StringInterner,
        sourceManager: SourceManager?,
        diagnostics: DiagnosticEngine
    ) -> Bool {
        guard sema.stdlibProfile == .minimal else { return false }
        let dotted = importDecl.path.map { interner.resolve($0) }.joined(separator: ".")
        guard StdlibProfile.isExcludedFromMinimal(package: dotted) else { return false }
        // A user file may declare its own package under an excluded prefix.
        if !(topLevelSymbolsByPackage[importDecl.path] ?? []).isEmpty { return false }
        let resolved = resolveExplicitImport(
            importDecl.path, sema: sema, interner: interner, sourceManager: sourceManager
        )
        let declaredByUser = resolved.contains { id in
            guard let symbol = sema.symbols.symbol(id), symbol.kind != .package else { return false }
            return !symbol.flags.contains(.synthetic) && !symbol.flags.contains(.importedLibrary)
        }
        if declaredByUser { return false }
        diagnostics.error(
            "KSWIFTK-LIB-0036",
            "Import '\(dotted)\(importDecl.isWildcard ? ".*" : "")' is not available in the minimal stdlib profile "
                + "(--profile minimal); compile without --profile minimal to use it.",
            range: importDecl.range
        )
        return true
    }

    private func resolveExplicitImport(
        _ path: [InternedString],
        sema: SemaModule,
        interner: StringInterner,
        sourceManager: SourceManager?
    ) -> [SymbolID] {
        let resolved = sema.symbols.lookupAll(fqName: path)
        guard resolved.isEmpty, let name = path.last else { return resolved }
        // Java static methods are represented by companion stubs. Only imported
        // JVM declarations admit the Java spelling Owner.method in an import.
        let jvmStaticMembers = sema.symbols.lookupAll(fqName: Array(path.dropLast())).flatMap { owner -> [SymbolID] in
            guard let declaration = sema.symbols.symbol(owner),
                  declaration.kind == .class || declaration.kind == .interface,
                  let site = declaration.declSite,
                  sourceManager?.origin(of: site.start.file) == .residualStdlib,
                  let filePath = sourceManager?.path(of: site.start.file),
                  filePath.hasPrefix("<kswiftk-jvm-import>/") || filePath.hasPrefix("<kswiftk-jvm>/platform/")
            else { return [] }
            return sema.symbols.lookupAll(fqName: declaration.fqName + [interner.intern("Companion"), name]).filter {
                sema.symbols.symbol($0)?.kind == .function
            }
        }
        if !jvmStaticMembers.isEmpty { return jvmStaticMembers }
        // Kotlin permits companion members to be imported through the owning
        // class name, even though their declarations belong to the companion.
        let companionMembers = sema.symbols.lookupAll(fqName: Array(path.dropLast())).flatMap { owner -> [SymbolID] in
            guard let declaration = sema.symbols.symbol(owner) else { return [] }
            switch declaration.kind {
            case .class, .interface, .enumClass, .annotationClass:
                break
            default:
                return []
            }
            guard let companionID = sema.symbols.companionObjectSymbol(for: owner),
                  let companion = sema.symbols.symbol(companionID)
            else { return [] }
            return sema.symbols.lookupAll(fqName: companion.fqName + [name]).filter { member in
                guard let kind = sema.symbols.symbol(member)?.kind else { return false }
                return kind == .function || kind == .property || kind == .field
            }
        }
        if !companionMembers.isEmpty {
            return Array(Set(companionMembers)).sorted { $0.rawValue < $1.rawValue }
        }
        // Bundled companion constants are package-owned extension properties.
        // Resolve the qualifier as a singleton and retain only its extensions,
        // rather than falling back to unrelated same-name package properties.
        let owners = Set(sema.symbols.lookupAll(fqName: Array(path.dropLast())).filter {
            sema.symbols.symbol($0)?.kind == .object
        })
        guard !owners.isEmpty else { return [] }
        let helpers = TypeCheckHelpers()
        var candidates: Set<SymbolID> = []
        for owner in owners {
            let ownerType = sema.types.make(.classType(ClassType(
                classSymbol: owner,
                args: [],
                nullability: .nonNull
            )))
            candidates.formUnion(helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: ownerType,
                sema: sema,
                interner: interner
            ))
            if let property = helpers.lookupMemberProperty(
                named: name,
                receiverType: ownerType,
                sema: sema
            ) {
                candidates.insert(property.symbol)
            }

            var ownerQueue = [owner]
            var visitedOwners: Set<SymbolID> = []
            while !ownerQueue.isEmpty {
                let memberOwner = ownerQueue.removeFirst()
                guard visitedOwners.insert(memberOwner).inserted,
                      let memberOwnerInfo = sema.symbols.symbol(memberOwner)
                else {
                    continue
                }
                candidates.formUnion(sema.symbols.lookupAll(fqName: memberOwnerInfo.fqName + [name]).filter {
                    sema.symbols.symbol($0)?.kind == .property
                        && sema.symbols.symbol($0)?.flags.contains(.memberExtension) == true
                })
                ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: memberOwner))
            }
        }

        // Bundled companion constants are package-owned extension properties,
        // not inherited nominal members. Preserve that import form after adding
        // the ordinary inherited-member candidates above.
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
            if sema.symbols.parentSymbol(for: candidate).map({ owners.contains($0) }) == true
                || sema.symbols.parentSymbol(for: candidate).map({ owner in
                    owners.contains { sema.types.isNominalSubtypeSymbol($0, of: owner) }
                }) == true {
                return true
            }
            guard sema.symbols.symbol(candidate)?.kind == .property,
                  let receiver = sema.symbols.extensionPropertyReceiverType(for: candidate),
                  case let .classType(receiverClass) = sema.types.kind(of: receiver)
            else { return false }
            return owners.contains(receiverClass.classSymbol)
        }
    }

    /// Kotlin/Native declares some APIs (`NativePlacement.allocArray`,
    /// `String.cstr`) as top-level extensions that are importable by package
    /// path, while the compiler models them as synthetic member extensions of a
    /// class in the same package. Such imports are valid; the declarations stay
    /// reachable through their receiver, so nothing is added to the scope.
    private func isSyntheticMemberExtensionImport(_ path: [InternedString], sema: SemaModule) -> Bool {
        guard path.count >= 2, let name = path.last else { return false }
        let package = Array(path.dropLast())
        return sema.symbols.lookupByShortName(name).contains { id in
            guard let symbol = sema.symbols.symbol(id),
                  symbol.flags.contains(.synthetic),
                  symbol.fqName.count == package.count + 2,
                  Array(symbol.fqName.prefix(package.count)) == package
            else { return false }
            switch symbol.kind {
            case .function:
                return sema.symbols.functionSignature(for: id)?.receiverType != nil
            case .property:
                return symbol.flags.contains(.memberExtension)
            default:
                return false
            }
        }
    }

    func populateImportScopes(
        for file: ASTFile,
        sema: SemaModule,
        explicitImportScope: ImportScope,
        wildcardImportScope: PackageMembersScope,
        topLevelSymbolsByPackage: [[InternedString]: [SymbolID]],
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) {
        var usedAliasNames: Set<InternedString> = []
        // Aliases bound only to functions may be reused: Kotlin merges
        // same-named function imports into one overload set.
        var functionOnlyAliasNames: Set<InternedString> = []
        let suppressesInvisibleAccess = file.annotations.contains { annotation in
            KnownCompilerAnnotation.suppress.matches(annotation.name) && annotation.arguments.contains {
                let code = $0.filter { $0 != "\"" && $0 != "'" }
                return code == "INVISIBLE_MEMBER" || code == "INVISIBLE_REFERENCE"
            }
        }
        let visibility = VisibilityChecker(
            symbols: sema.symbols, sourceManager: sourceManager, diagnostics: diagnostics, interner: interner,
            invisibleAccessFiles: suppressesInvisibleAccess ? [file.fileID.rawValue] : []
        )
        // Bundled stdlib source contains platform-specific imports (for
        // example, Java interop types) that are intentionally absent from the
        // compiler's symbol graph. Import validation is for user source only.
        let validatesImports = sourceManager?.origin(of: file.fileID)?.isBundledStdlib != true
        func isAccessibleWildcardSymbol(_ id: SymbolID) -> Bool {
            guard let symbol = sema.symbols.symbol(id) else { return false }
            // Internal library declarations can be imported through a
            // wildcard; visibility is checked at the use site so local
            // @Suppress annotations can enable individual references.
            if symbol.visibility == .internal {
                return true
            }
            return visibility.isAccessible(symbol, fromFile: file.fileID, enclosingClass: nil)
        }
        func validateExplicitImport(_ resolved: [SymbolID], range: SourceRange?) -> Bool {
            guard validatesImports else { return true }
            let declarations = resolved.compactMap { sema.symbols.symbol($0) }.filter { $0.kind != .package }
            func inaccessibleOwner(of symbol: SemanticSymbol) -> SemanticSymbol? {
                var chain = [symbol]
                var seen: Set<SymbolID> = [symbol.id]
                var current = symbol
                while let parent = sema.symbols.parentSymbol(for: current.id),
                      seen.insert(parent).inserted, let owner = sema.symbols.symbol(parent) {
                    chain.append(owner)
                    current = owner
                }
                return chain.reversed().first {
                    !visibility.isAccessible($0, fromFile: file.fileID, enclosingClass: nil)
                }
            }
            guard !declarations.isEmpty, declarations.allSatisfy({ inaccessibleOwner(of: $0) != nil }),
                  let declaration = declarations.first, let inaccessible = inaccessibleOwner(of: declaration)
            else { return true }
            // Nested private declarations are resolved at the import site but
            // their accessibility depends on the body that uses the import.
            // Keep rejecting file-private top-level declarations from other
            // files; only defer a private owner nested inside another nominal.
            if inaccessible.visibility == .private,
               let parent = sema.symbols.parentSymbol(for: inaccessible.id),
               let owner = sema.symbols.symbol(parent),
               owner.kind != .package {
                return true
            }
            // Kotlin permits importing internal declarations; visibility is
            // reported at each reference so local @Suppress annotations work.
            if inaccessible.visibility == .internal {
                return true
            }
            let code: String = switch inaccessible.visibility {
            case .private: "KSWIFTK-SEMA-0040"
            case .protected: "KSWIFTK-SEMA-0041"
            case .internal: "KSWIFTK-SEMA-0044"
            case .public: "KSWIFTK-SEMA-0040"
            }
            diagnostics.error(
                code, "Cannot import inaccessible declaration '\(interner.resolve(inaccessible.name))'.",
                range: range
            )
            return false
        }

        for importDecl in file.imports {
            if validatesImports,
               reportMinimalProfileExcludedImport(
                   importDecl,
                   topLevelSymbolsByPackage: topLevelSymbolsByPackage,
                   sema: sema,
                   interner: interner,
                   sourceManager: sourceManager,
                   diagnostics: diagnostics
               )
            {
                continue
            }
            if let alias = importDecl.alias {
                if interner.resolve(alias).isEmpty {
                    continue
                }

                let resolved = resolveExplicitImport(importDecl.path, sema: sema, interner: interner, sourceManager: sourceManager)

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
                        "KSWIFTK-SEMA-UNRESOLVED-IMPORT",
                        "Unresolved import path.",
                        range: importDecl.range
                    )
                    continue
                }

                let isFunctionOnlyImport = resolved.allSatisfy {
                    sema.symbols.symbol($0)?.kind == .function
                }
                if usedAliasNames.contains(alias),
                   !(isFunctionOnlyImport && functionOnlyAliasNames.contains(alias))
                {
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
                guard validateExplicitImport(importedSymbols, range: importDecl.range) else { continue }

                for importedSymbol in importedSymbols {
                    explicitImportScope.insertWithAlias(importedSymbol, asName: alias)
                }

                if !usedAliasNames.contains(alias) || functionOnlyAliasNames.contains(alias),
                   isFunctionOnlyImport
                {
                    functionOnlyAliasNames.insert(alias)
                } else {
                    functionOnlyAliasNames.remove(alias)
                }
                usedAliasNames.insert(alias)
                continue
            }

            let resolved = importDecl.isWildcard
                ? sema.symbols.lookupAll(fqName: importDecl.path)
                : resolveExplicitImport(importDecl.path, sema: sema, interner: interner, sourceManager: sourceManager)
            let wildcardEnumOwners = importDecl.isWildcard
                ? enumOwnersForWildcardImport(resolved, sema: sema, isAccessibleSymbol: isAccessibleWildcardSymbol)
                : []
            if !wildcardEnumOwners.isEmpty {
                // Enum entries belong to the enum, not a package. Source entries
                // are deliberately absent from the package-only symbol index.
                for enumID in wildcardEnumOwners {
                    for entry in sema.symbols.declaredChildren(of: enumID)
                        where sema.symbols.symbol(entry)?.kind == .field && isAccessibleWildcardSymbol(entry) {
                        wildcardImportScope.insert(entry)
                    }
                }
            }
            if resolved.isEmpty {
                let packageSymbols = topLevelSymbolsByPackage[importDecl.path] ?? []
                // Compact-index packages are not registered until a lookup
                // reaches them; check the index without draining so an
                // unresolved-import diagnostic never fires on a real package.
                let indexHasMembers = sema.symbols.libraryIndexContainsEntriesNested(
                    under: importDecl.path
                )
                if packageSymbols.isEmpty, !indexHasMembers, !importDecl.isWildcard, validatesImports,
                   !isSyntheticMemberExtensionImport(importDecl.path, sema: sema)
                {
                    diagnostics.error(
                        "KSWIFTK-SEMA-UNRESOLVED-IMPORT",
                        "Unresolved import path.",
                        range: importDecl.range
                    )
                }
                if !packageSymbols.isEmpty || indexHasMembers {
                    for packageSymbol in packageSymbols {
                        if shouldSkipDefaultImport(packageSymbol, sema: sema) {
                            continue
                        }
                        if !isAccessibleWildcardSymbol(packageSymbol) { continue }
                        wildcardImportScope.insert(packageSymbol)
                    }
                    wildcardImportScope.addPackage(importDecl.path) { [self, sema] symbolID in
                        !shouldSkipDefaultImport(symbolID, sema: sema)
                            && isAccessibleWildcardSymbol(symbolID)
                    }
                }
                continue
            }

            // A JDK static facade (`java.lang.Math`, `java.util.Arrays`, ...)
            // is modelled as an object, but Kotlin/JVM admits star imports of
            // its static members. Contribute the object's callable members at
            // wildcard priority before the generic object-import rejection.
            if importDecl.isWildcard,
               let facadeOwner = resolved.first(where: { symbolID in
                   sema.symbols.symbol(symbolID).map { isJavaStaticFacade($0, interner: interner) } == true
               })
            {
                importJavaStaticFacadeMembers(
                    facadeOwner,
                    wildcardImportScope: wildcardImportScope,
                    sema: sema,
                    isAccessibleWildcardSymbol: isAccessibleWildcardSymbol
                )
                continue
            }

            if importDecl.isWildcard {
                for owner in resolved {
                    guard let companion = sema.symbols.companionObjectSymbolIfKnown(for: owner),
                          isAccessibleWildcardSymbol(owner) else { continue }
                    for member in sema.symbols.declaredChildren(of: companion)
                        where sema.symbols.isJVMJavaMethod(member) && isAccessibleWildcardSymbol(member) {
                        wildcardImportScope.insert(member)
                    }
                }
            }

            if importDecl.isWildcard, validatesImports,
               let importedObject = resolved.first(where: { sema.symbols.symbol($0)?.kind == .object }),
               let object = sema.symbols.symbol(importedObject)
            {
                diagnostics.error(
                    "KSWIFTK-SEMA-0027",
                    "Cannot import on demand from object '\(interner.resolve(object.name))'.",
                    range: importDecl.range
                )
                continue
            }

            if importDecl.isWildcard {
                let enumOwners = enumOwnersForWildcardImport(
                    resolved, sema: sema, isAccessibleSymbol: isAccessibleWildcardSymbol
                )
                if !enumOwners.isEmpty {
                    // Enum star imports introduce entries at wildcard priority,
                    // not the enum type or its instance/companion members.
                    for enumOwner in enumOwners {
                        var owner: SymbolID? = enumOwner
                        var isAccessibleOwner = true
                        while let current = owner {
                            if !isAccessibleWildcardSymbol(current) {
                                isAccessibleOwner = false
                                break
                            }
                            owner = sema.symbols.parentSymbol(for: current)
                        }
                        guard isAccessibleOwner,
                              sema.symbols.symbol(enumOwner) != nil
                        else { continue }
                        for entry in sema.symbols.declaredChildren(of: enumOwner) {
                            guard sema.symbols.symbol(entry)?.kind == .field,
                                  isAccessibleWildcardSymbol(entry)
                            else { continue }
                            wildcardImportScope.insert(entry)
                        }
                    }
                    continue
                }
            }

            // A star import whose path resolves to a nested classifier imports
            // that classifier's nested classifiers, not the owner itself. Keep
            // visibility contextual here: a private nested owner can be
            // accessible from one enclosing class in the file and inaccessible
            // from another use site.
            let wildcardClassifierOwners = importDecl.isWildcard ? resolved.filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                switch symbol.kind {
                case .class, .interface, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            } : []
            for owner in wildcardClassifierOwners.sorted(by: { $0.rawValue < $1.rawValue }) {
                for member in sema.symbols.children(of: owner) {
                    guard let symbol = sema.symbols.symbol(member) else { continue }
                    switch symbol.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        wildcardImportScope.insert(member)
                    default:
                        continue
                    }
                }
            }

            let hasPackageImport = resolved.contains { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .package
            }
            let importedSymbols = resolved.filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                return symbol.kind != .package && !wildcardClassifierOwners.contains(symbolID)
            }
            if !importedSymbols.isEmpty, !hasPackageImport {
                guard validateExplicitImport(importedSymbols, range: importDecl.range) else { continue }
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
                continue
            }
            if !importedSymbols.isEmpty, hasPackageImport {
                guard validateExplicitImport(importedSymbols, range: importDecl.range) else { continue }
                for importedSymbol in importedSymbols {
                    explicitImportScope.insert(importedSymbol)
                }
            }

            // A non-wildcard import resolving to a declaration must not dump
            // that declaration's neighbours into the wildcard scope, even when
            // a synthetic package record shares its FQ name (KUU-1205).
            if sema.symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
                for importedSymbol in topLevelSymbolsByPackage[importDecl.path] ?? [] {
                    if shouldSkipDefaultImport(importedSymbol, sema: sema) {
                        continue
                    }
                    if !isAccessibleWildcardSymbol(importedSymbol) { continue }
                    wildcardImportScope.insert(importedSymbol)
                }
                wildcardImportScope.addPackage(importDecl.path) { [self, sema] symbolID in
                    !shouldSkipDefaultImport(symbolID, sema: sema)
                        && isAccessibleWildcardSymbol(symbolID)
                }
            }
        }
    }

    func collectLibraryTopLevelSymbolsByPackage(
        sema: SemaModule) -> [[InternedString]: [SymbolID]] {
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
            if isSyntheticOperatorExtensionToExclude(symbol.id, sema: sema) {
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
        sema: SemaModule
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.kind == .function,
              symbol.flags.contains(.operatorFunction),
              symbol.flags.contains(.synthetic),
              !sema.symbols.isSourceBackedSymbol(symbolID),
              let signature = sema.symbols.functionSignature(for: symbolID),
              signature.receiverType != nil
        else {
            return false
        }

        return true
    }

    /// Includes the synthetic operator extensions covered by STDLIB-SHARED-009.
    /// Member-style and operator syntax (e.g. `cs[0]`) resolve source-backed
    /// interface members normally.
    private func shouldSkipDefaultImport(
        _ symbolID: SymbolID,
        sema: SemaModule) -> Bool {
        if isSyntheticOperatorExtensionToExclude(symbolID, sema: sema) {
            return true
        }

        return false
    }

    /// Keep Java's primitive wrappers and String available by qualified name,
    /// but do not let the `java.lang.*` default import shadow Kotlin types.
    private func shouldSkipMappedJavaLangTypeDefaultImport(
        _ symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID),
              symbol.kind == .class || symbol.kind == .typeAlias
        else {
            return false
        }
        let fqName = symbol.fqName.map { interner.resolve($0) }
        guard fqName.count == 3, fqName[0] == "java", fqName[1] == "lang" else {
            return false
        }
        return ["Boolean", "Byte", "Double", "Float", "Long", "Short", "String"].contains(fqName[2])
    }

    func makeDefaultImportPackages(interner: StringInterner) -> [[InternedString]] {
        let packages: [[String]] = [
            ["kotlin"],
            ["kotlin", "annotation"],
            ["kotlin", "collections"],
            ["kotlin", "comparisons"],
            ["kotlin", "coroutines"],
            ["kotlin", "native"],
            // kotlin.math is not a Kotlin default import; importing it here broke
            // member resolution for java.security.Signature.sign vs kotlin.math.sign.
            ["kotlin", "io"],
            ["kotlin", "jvm"],
            ["kotlin", "ranges"],
            ["kotlin", "sequences"],
            ["kotlin", "text"],
            ["kotlin", "time"],
            ["java", "lang"],
        ]
        return packages.map { segments in
            segments.map { interner.intern($0) }
        }
    }

    /// FQ names of Kotlin's builtin classifiers — the `KotlinBuiltIns`
    /// package contents (function types, primitives and their arrays, the
    /// mapped `kotlin.collections` interfaces, ranges and progressions,
    /// `kotlin.sequences`, and the builtin annotation/text types). During
    /// classifier lookup these resolve above user star imports, while
    /// ordinary default imports rank below them: under `import java.util.*`
    /// `Iterator` still binds `kotlin.collections.Iterator` but
    /// `ArrayDeque` binds `java.util.ArrayDeque` (KUU-4509).
    private func kotlinBuiltinClassifierFQNames(interner: StringInterner) -> Set<[InternedString]> {
        let names: [[String]] = [
            ["kotlin", "Any"], ["kotlin", "Nothing"], ["kotlin", "Unit"],
            ["kotlin", "Boolean"], ["kotlin", "Char"], ["kotlin", "String"],
            ["kotlin", "CharSequence"], ["kotlin", "Comparable"], ["kotlin", "Comparator"],
            ["kotlin", "Throwable"], ["kotlin", "Enum"], ["kotlin", "Annotation"],
            ["kotlin", "Number"], ["kotlin", "Function"], ["kotlin", "Result"],
            ["kotlin", "Cloneable"], ["kotlin", "EnumEntries"], ["kotlin", "DeepRecursiveFunction"],
            ["kotlin", "Byte"], ["kotlin", "Short"], ["kotlin", "Int"],
            ["kotlin", "Long"], ["kotlin", "Float"], ["kotlin", "Double"],
            ["kotlin", "UByte"], ["kotlin", "UShort"], ["kotlin", "UInt"], ["kotlin", "ULong"],
            ["kotlin", "Array"], ["kotlin", "BooleanArray"], ["kotlin", "ByteArray"],
            ["kotlin", "CharArray"], ["kotlin", "ShortArray"], ["kotlin", "IntArray"],
            ["kotlin", "LongArray"], ["kotlin", "FloatArray"], ["kotlin", "DoubleArray"],
            ["kotlin", "UByteArray"], ["kotlin", "UShortArray"],
            ["kotlin", "UIntArray"], ["kotlin", "ULongArray"],
            ["kotlin", "collections", "Iterator"], ["kotlin", "collections", "MutableIterator"],
            ["kotlin", "collections", "Iterable"], ["kotlin", "collections", "MutableIterable"],
            ["kotlin", "collections", "Collection"], ["kotlin", "collections", "MutableCollection"],
            ["kotlin", "collections", "List"], ["kotlin", "collections", "MutableList"],
            ["kotlin", "collections", "ListIterator"], ["kotlin", "collections", "MutableListIterator"],
            ["kotlin", "collections", "Set"], ["kotlin", "collections", "MutableSet"],
            ["kotlin", "collections", "Map"], ["kotlin", "collections", "MutableMap"],
            ["kotlin", "collections", "Map", "Entry"],
            ["kotlin", "collections", "MutableMap", "MutableEntry"],
            ["kotlin", "ranges", "ClosedRange"], ["kotlin", "ranges", "ClosedFloatingPointRange"],
            ["kotlin", "ranges", "OpenEndRange"], ["kotlin", "ranges", "CharRange"],
            ["kotlin", "ranges", "IntRange"], ["kotlin", "ranges", "LongRange"],
            ["kotlin", "ranges", "UIntRange"], ["kotlin", "ranges", "ULongRange"],
            ["kotlin", "ranges", "CharProgression"], ["kotlin", "ranges", "IntProgression"],
            ["kotlin", "ranges", "LongProgression"], ["kotlin", "ranges", "UIntProgression"],
            ["kotlin", "ranges", "ULongProgression"],
            ["kotlin", "sequences", "Sequence"],
            ["kotlin", "annotation", "AnnotationTarget"], ["kotlin", "annotation", "AnnotationRetention"],
            ["kotlin", "annotation", "Target"], ["kotlin", "annotation", "Retention"],
            ["kotlin", "annotation", "Repeatable"], ["kotlin", "annotation", "MustBeDocumented"],
            ["kotlin", "text", "CharCategory"], ["kotlin", "text", "Regex"],
            ["kotlin", "text", "MatchResult"], ["kotlin", "text", "MatchGroup"],
            ["kotlin", "text", "MatchGroupCollection"], ["kotlin", "text", "MatchNamedGroupCollection"],
            ["kotlin", "text", "StringBuilder"], ["kotlin", "text", "Appendable"],
            ["kotlin", "text", "Typography"],
        ]
        return Set(names.map { $0.map(interner.intern) })
    }
}
