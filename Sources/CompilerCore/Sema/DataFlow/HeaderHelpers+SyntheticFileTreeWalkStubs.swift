
/// Synthetic stubs for kotlin.io.FileTreeWalk (STDLIB-IO-TYPE-004).
///
/// Registers:
///   - `kotlin.io.FileTreeWalk` class with builder and traversal methods
///   - `File.walkTopDown()` → `kk_file_walkTopDown` (direction = TOP_DOWN)
///   - `File.walkBottomUp()` → `kk_file_walkBottomUp` (direction = BOTTOM_UP)
///   - `FileTreeWalk.maxDepth(Int)`, `.filter`, `.onEnter`, `.onLeave`, `.onFail`
///     (all return `FileTreeWalk` — immutable builder chain)
///   - `FileTreeWalk.toList()` → `List<File>` (materialises the walk)
///   - `FileTreeWalk.forEach((File)->Unit)` → `Unit`
///
/// `File.walk()` is intentionally left mapped to `kk_file_walk → List<File>`
/// (see HeaderHelpers+SyntheticFileIOStubs.swift) to preserve existing callers
/// and the LoweringPassRegressionTests that assert `callees.contains("kk_file_walk")`.
///
/// Registration must run AFTER `registerSyntheticFileIOStubs` so that the
/// `java.io.File` and `kotlin.io` package symbols already exist.
extension DataFlowSemaPhase {
    func registerSyntheticFileTreeWalkStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Resolve pre-registered symbols.
        let javaIOPkg = ensurePackage(path: ["java", "io"], symbols: symbols, interner: interner)
        let fileSymbol = ensureClassSymbol(named: "File", in: javaIOPkg, symbols: symbols, interner: interner)
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))

        // Register FileTreeWalk in kotlin.io.
        let kotlinIOPkg = ensurePackage(path: ["kotlin", "io"], symbols: symbols, interner: interner)
        let walkSymbol = ensureClassSymbol(
            named: "FileTreeWalk",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let pkgSym = symbols.lookup(fqName: kotlinIOPkg) {
            symbols.setParentSymbol(pkgSym, for: walkSymbol)
        }
        let walkType = types.make(.classType(ClassType(
            classSymbol: walkSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(walkType, for: walkSymbol)

        // List<File> for toList() return type.
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        let listSym = symbols.lookup(fqName: listFQName)
        let listOfFileType: TypeID = if let ls = listSym {
            types.make(.classType(ClassType(
                classSymbol: ls, args: [.out(fileType)], nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        // Lambda types used by builder callbacks.
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

        // onFail takes (File, IOException/Throwable) -> Unit.
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let throwableSymbol = ensureClassSymbol(
            named: "Throwable", in: kotlinPkg, symbols: symbols, interner: interner
        )
        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol, args: [], nullability: .nonNull
        )))
        let fileAndThrowableToUnitType = types.make(.functionType(FunctionType(
            params: [fileType, throwableType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        // MARK: - File.walkTopDown() / File.walkBottomUp()

        registerFileTreeWalkFunction(
            named: "walkTopDown",
            externalLinkName: "kk_file_walkTopDown",
            ownerSymbol: fileSymbol,
            receiverType: fileType,
            parameters: [],
            returnType: walkType,
            symbols: symbols,
            interner: interner
        )

        registerFileTreeWalkFunction(
            named: "walkBottomUp",
            externalLinkName: "kk_file_walkBottomUp",
            ownerSymbol: fileSymbol,
            receiverType: fileType,
            parameters: [],
            returnType: walkType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - FileTreeWalk builder methods (return new FileTreeWalk)

        registerFileTreeWalkFunction(
            named: "maxDepth",
            externalLinkName: "kk_file_tree_walk_maxDepth",
            ownerSymbol: walkSymbol,
            receiverType: walkType,
            parameters: [("depth", types.intType)],
            returnType: walkType,
            symbols: symbols,
            interner: interner
        )

        registerFileTreeWalkFunction(
            named: "filter",
            externalLinkName: "kk_file_tree_walk_filter",
            ownerSymbol: walkSymbol,
            receiverType: walkType,
            parameters: [("predicate", fileToBoolType)],
            returnType: walkType,
            symbols: symbols,
            interner: interner
        )

        registerFileTreeWalkFunction(
            named: "onEnter",
            externalLinkName: "kk_file_tree_walk_onEnter",
            ownerSymbol: walkSymbol,
            receiverType: walkType,
            parameters: [("function", fileToBoolType)],
            returnType: walkType,
            symbols: symbols,
            interner: interner
        )

        registerFileTreeWalkFunction(
            named: "onLeave",
            externalLinkName: "kk_file_tree_walk_onLeave",
            ownerSymbol: walkSymbol,
            receiverType: walkType,
            parameters: [("function", fileToUnitType)],
            returnType: walkType,
            symbols: symbols,
            interner: interner
        )

        registerFileTreeWalkFunction(
            named: "onFail",
            externalLinkName: "kk_file_tree_walk_onFail",
            ownerSymbol: walkSymbol,
            receiverType: walkType,
            parameters: [("function", fileAndThrowableToUnitType)],
            returnType: walkType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - FileTreeWalk terminal operations

        registerFileTreeWalkFunction(
            named: "toList",
            externalLinkName: "kk_file_tree_walk_toList",
            ownerSymbol: walkSymbol,
            receiverType: walkType,
            parameters: [],
            returnType: listOfFileType,
            symbols: symbols,
            interner: interner
        )

        registerFileTreeWalkFunction(
            named: "forEach",
            externalLinkName: "kk_file_tree_walk_forEach",
            ownerSymbol: walkSymbol,
            receiverType: walkType,
            parameters: [("action", fileToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Private registration helper

    private func registerFileTreeWalkFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let funcName = interner.intern(name)
        let fqName = ownerInfo.fqName + [funcName]

        let alreadyRegistered = symbols.lookupAll(fqName: fqName).contains { candidate in
            guard let sym = symbols.symbol(candidate),
                  sym.kind == .function,
                  let sig = symbols.functionSignature(for: candidate)
            else { return false }
            return sig.receiverType == receiverType
                && sig.parameterTypes == parameters.map(\.type)
        }
        if alreadyRegistered { return }

        let funcSym = symbols.define(
            kind: .function,
            name: funcName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSym)
        symbols.setExternalLinkName(externalLinkName, for: funcSym)

        var paramTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for param in parameters {
            let pName = interner.intern(param.name)
            let pSym = symbols.define(
                kind: .valueParameter,
                name: pName,
                fqName: fqName + [pName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(funcSym, for: pSym)
            paramTypes.append(param.type)
            paramSymbols.append(pSym)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: paramTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: funcSym
        )
    }
}
