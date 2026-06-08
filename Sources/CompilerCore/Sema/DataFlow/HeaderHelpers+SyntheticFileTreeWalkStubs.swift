
/// Synthetic stub for kotlin.io.FileTreeWalk (STDLIB-IO-TYPE-004).
///
/// `FileTreeWalk` is a Kotlin stdlib class in the `kotlin.io` package that
/// implements `Sequence<File>`. It is the return type of:
/// - `File.walkTopDown(): FileTreeWalk`
/// - `File.walkBottomUp(): FileTreeWalk`
/// - `File.walk(direction: FileWalkDirection): FileTreeWalk`
///
/// This stub registers the class and its key members in the symbol table so
/// that name resolution and type checking succeed for code that calls
/// `walkTopDown()`, `walkBottomUp()`, `walk(direction)`, and chains
/// `.maxDepth()` or `.toList()` on the result.
///
/// Registration runs after `registerSyntheticFileWalkDirectionStubs` (which
/// ensures `FileWalkDirection` exists) and after `registerSyntheticFileIOStubs`
/// (which ensures `java.io.File` and `kotlin.io` package exist).
///
/// NOTE: The zero-argument `File.walk()` overload registered in
/// `HeaderHelpers+SyntheticFileIOStubs.swift` intentionally returns `List<File>`
/// to preserve existing golden test output. Only the new overloads added here
/// return `FileTreeWalk`.
extension DataFlowSemaPhase {
    func registerSyntheticFileTreeWalkStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinIOPkg = ensurePackage(
            path: ["kotlin", "io"],
            symbols: symbols,
            interner: interner
        )

        // Look up java.io.File (registered by registerSyntheticFileIOStubs)
        let javaIOFileFQName = ["java", "io", "File"].map { interner.intern($0) }
        guard let fileSymbol = symbols.lookup(fqName: javaIOFileFQName),
              let fileType = symbols.propertyType(for: fileSymbol)
        else {
            assertionFailure("java.io.File not found; FileTreeWalk stubs require FileIO stubs to run first")
            return
        }

        // Build List<File> type for toList() return
        let listSymbol = resolveListSymbolForFileTreeWalk(symbols: symbols, interner: interner)
        let listOfFileType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(fileType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        // Define kotlin.io.FileTreeWalk as a synthetic class
        let fileTreeWalkSymbol = ensureFileTreeWalkClassSymbol(
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        let fileTreeWalkType = types.make(.classType(ClassType(
            classSymbol: fileTreeWalkSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileTreeWalkType, for: fileTreeWalkSymbol)

        // FileTreeWalk.toList(): List<File>
        registerFileMemberFunction(
            named: "toList",
            externalLinkName: "kk_file_tree_walk_to_list",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [],
            returnType: listOfFileType,
            symbols: symbols,
            interner: interner
        )

        // FileTreeWalk.maxDepth(depth: Int): FileTreeWalk
        registerFileMemberFunction(
            named: "maxDepth",
            externalLinkName: "kk_file_tree_walk_max_depth",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("depth", types.intType)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // File.walkTopDown(): FileTreeWalk
        registerFileMemberFunction(
            named: "walkTopDown",
            externalLinkName: "kk_file_walkTopDown",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // File.walkBottomUp(): FileTreeWalk
        registerFileMemberFunction(
            named: "walkBottomUp",
            externalLinkName: "kk_file_walkBottomUp",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // File.walk(direction: FileWalkDirection): FileTreeWalk
        let fileWalkDirectionFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
        if let directionSymbol = symbols.lookup(fqName: fileWalkDirectionFQName),
           let directionType = symbols.propertyType(for: directionSymbol) {
            registerFileMemberFunction(
                named: "walk",
                externalLinkName: "kk_file_walk_with_direction",
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("direction", directionType)],
                returnType: fileTreeWalkType,
                symbols: symbols,
                interner: interner
            )
        }
    }

    // MARK: - Private helpers

    private func ensureFileTreeWalkClassSymbol(
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("FileTreeWalk")
        let fqName = pkg + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        let classSymbol = symbols.define(
            kind: .class,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: pkg), pkgSymbol != .invalid {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }
        return classSymbol
    }

    private func resolveListSymbolForFileTreeWalk(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        return symbols.lookup(fqName: listFQName)
    }
}
