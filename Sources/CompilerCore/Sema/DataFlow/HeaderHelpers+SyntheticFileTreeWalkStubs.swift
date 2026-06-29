/// Synthetic stub for kotlin.io.FileTreeWalk (STDLIB-IO-TYPE-004).
///
/// `FileTreeWalk` is a Kotlin stdlib class in the `kotlin.io` package that
/// implements `Sequence<File>`. It is the return type of:
/// - `File.walkTopDown(): FileTreeWalk`
/// - `File.walkBottomUp(): FileTreeWalk`
/// - `File.walk(direction: FileWalkDirection): FileTreeWalk`
/// - `File.walk(): FileTreeWalk`
///
/// This stub registers the class and its key members in the symbol table so
/// that name resolution and type checking succeed for code that calls
/// `walkTopDown()`, `walkBottomUp()`, `walk(direction)`, and chains
/// `.maxDepth()`, `.filter()`, `.onEnter()`, `.onLeave()`, `.onFail()`,
/// `.toList()`, or `.forEach()` on the result.
///
/// Registration runs after `registerSyntheticFileWalkDirectionStubs` (which
/// ensures `FileWalkDirection` exists) and after `registerSyntheticFileIOStubs`
/// (which ensures `java.io.File` and `kotlin.io` package exist).
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

        // Look up java.io.File (registered by registerSyntheticFileIOStubs).
        // Returns early if File is not available — File.walkTopDown/walkBottomUp/walk(direction:)
        // members cannot be registered without it, but the FileTreeWalk class itself is still valid.
        let javaIOFileFQName = ["java", "io", "File"].map { interner.intern($0) }
        guard let fileSymbol = symbols.lookup(fqName: javaIOFileFQName),
              let fileType = symbols.propertyType(for: fileSymbol)
        else { return }

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

        // Lambda types used by builder callbacks
        let fileToBoolType = types.make(.functionType(FunctionType(
            params: [fileType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fileToUnitType = types.make(.functionType(FunctionType(
            params: [fileType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableType: TypeID = if let throwableSym = symbols.lookup(fqName: throwableFQName) {
            types.make(.classType(ClassType(classSymbol: throwableSym, args: [], nullability: .nonNull)))
        } else {
            types.anyType
        }
        let fileAndThrowableToUnitType = types.make(.functionType(FunctionType(
            params: [fileType, throwableType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

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

        // FileTreeWalk.filter((File) -> Boolean): FileTreeWalk
        registerFileMemberFunction(
            named: "filter",
            externalLinkName: "kk_file_tree_walk_filter",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("predicate", fileToBoolType)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // FileTreeWalk.onEnter((File) -> Boolean): FileTreeWalk
        registerFileMemberFunction(
            named: "onEnter",
            externalLinkName: "kk_file_tree_walk_onEnter",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("function", fileToBoolType)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // FileTreeWalk.onLeave((File) -> Unit): FileTreeWalk
        registerFileMemberFunction(
            named: "onLeave",
            externalLinkName: "kk_file_tree_walk_onLeave",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("function", fileToUnitType)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // FileTreeWalk.onFail((File, Throwable) -> Unit): FileTreeWalk
        registerFileMemberFunction(
            named: "onFail",
            externalLinkName: "kk_file_tree_walk_onFail",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("function", fileAndThrowableToUnitType)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // FileTreeWalk.forEach((File) -> Unit): Unit
        registerFileMemberFunction(
            named: "forEach",
            externalLinkName: "kk_file_tree_walk_forEach",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("action", fileToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // FileTreeWalk.sortedBy((File) -> Comparable<*>?): List<File>
        // FileTreeWalk implements Sequence<File>; sortedBy collects and sorts by selector.
        let fileToAnyType = types.make(.functionType(FunctionType(
            params: [fileType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerFileMemberFunction(
            named: "sortedBy",
            externalLinkName: "kk_file_tree_walk_sortedBy",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("selector", fileToAnyType)],
            returnType: listOfFileType,
            symbols: symbols,
            interner: interner
        )

        // Re-register File.walk() (zero-arg) with FileTreeWalk return type.
        // FileIOStubs registered it first (potentially with a listOfFile fallback); this updates it.
        registerFileMemberFunction(
            named: "walk",
            externalLinkName: "kk_file_walk",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
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

    /// Called by HeaderHelpers+SyntheticFileIOStubs to look up the FileTreeWalk type ID.
    func resolveFileTreeWalkType(symbols: SymbolTable, types: TypeSystem, interner: StringInterner) -> TypeID? {
        let kotlinIOPkg = ensurePackage(path: ["kotlin", "io"], symbols: symbols, interner: interner)
        let fqName = kotlinIOPkg + [interner.intern("FileTreeWalk")]
        guard let sym = symbols.lookup(fqName: fqName) else { return nil }
        return types.make(.classType(ClassType(classSymbol: sym, args: [], nullability: .nonNull)))
    }
}
