
/// Synthetic stubs for kotlin.io.FileTreeWalk (STDLIB-IO-TYPE-004).
///
/// Covers:
/// - `FileTreeWalk` class with builder methods: `maxDepth`, `onEnter`, `onLeave`, `onFail`
/// - `File.walkTopDown()` and `File.walkBottomUp()` extension functions
/// - Update of `File.walk()` return type from `List<File>` → `FileTreeWalk`
///
/// This stub must run after `registerSyntheticFileIOStubs` (which defines `java.io.File`)
/// and after `registerSyntheticFileWalkDirectionStubs` (which ensures `kotlin.io` exists).
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
        let kotlinIOPkgSymbol = symbols.lookup(fqName: kotlinIOPkg)

        // Retrieve java.io.File (registered by registerSyntheticFileIOStubs)
        let javaIOPkg: [InternedString] = [interner.intern("java"), interner.intern("io")]
        guard let fileSymbol = symbols.lookup(fqName: javaIOPkg + [interner.intern("File")]) else {
            return
        }
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))

        // kotlin.io.FileTreeWalk class
        let fileTreeWalkSymbol = ensureClassSymbol(
            named: "FileTreeWalk",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPkgSymbol {
            symbols.setParentSymbol(kotlinIOPkgSymbol, for: fileTreeWalkSymbol)
        }
        let fileTreeWalkType = types.make(.classType(ClassType(
            classSymbol: fileTreeWalkSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileTreeWalkType, for: fileTreeWalkSymbol)

        // Lambda parameter types for builder methods
        let fileToBoolean = types.make(.functionType(FunctionType(
            params: [fileType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fileToUnit = types.make(.functionType(FunctionType(
            params: [fileType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        // IOException is represented as Any; the Lowering pass threads the opaque
        // exception handle through unchanged.
        let fileAnyToUnit = types.make(.functionType(FunctionType(
            params: [fileType, types.anyType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        // MARK: - FileTreeWalk member functions

        // maxDepth(depth: Int): FileTreeWalk
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

        // onEnter(function: (File) -> Boolean): FileTreeWalk
        registerFileMemberFunction(
            named: "onEnter",
            externalLinkName: "kk_file_tree_walk_on_enter",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("function", fileToBoolean)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // onLeave(function: (File) -> Unit): FileTreeWalk
        registerFileMemberFunction(
            named: "onLeave",
            externalLinkName: "kk_file_tree_walk_on_leave",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("function", fileToUnit)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // onFail(function: (File, IOException) -> Unit): FileTreeWalk
        registerFileMemberFunction(
            named: "onFail",
            externalLinkName: "kk_file_tree_walk_on_fail",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("function", fileAnyToUnit)],
            returnType: fileTreeWalkType,
            symbols: symbols,
            interner: interner
        )

        // forEach(action: (File) -> Unit): Unit
        registerFileMemberFunction(
            named: "forEach",
            externalLinkName: "kk_file_tree_walk_for_each",
            ownerSymbol: fileTreeWalkSymbol,
            ownerType: fileTreeWalkType,
            parameters: [("action", fileToUnit)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File extension functions returning FileTreeWalk

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
    }
}
