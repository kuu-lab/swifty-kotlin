
extension DataFlowSemaPhase {
    /// A user-declared top-level `fun X(...)` whose value-parameter signature
    /// matches a constructor of a user-declared class `X` in the same package
    /// is a redeclaration (kotlinc: conflicting declarations). Factory-style
    /// functions with a different signature (e.g. `fun Random(seed: Long)`)
    /// stay legal. Called from both the class-constructor and the function
    /// header paths; only the later of the two sees both signatures.
    func checkAndReportClassConstructorFunctionConflict(
        classFQName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        func isUserSource(_ id: SymbolID) -> Bool {
            // Constructors carry no source file ID of their own; use their owner's.
            guard let fileID = symbols.sourceFileID(for: id)
                ?? symbols.parentSymbol(for: id).flatMap({ symbols.sourceFileID(for: $0) })
            else { return false }
            return sourceManager.origin(of: fileID)?.isBundledStdlib != true
        }
        let constructors = symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).compactMap { id -> FunctionSignature? in
            guard let symbol = symbols.symbol(id), symbol.kind == .constructor,
                  !symbol.flags.contains(.synthetic), isUserSource(id)
            else { return nil }
            return symbols.functionSignature(for: id)
        }
        guard !constructors.isEmpty else { return }
        func erased(_ signature: FunctionSignature) -> ([TypeID], [Bool]) {
            let flags = signature.valueParameterIsVararg.isEmpty
                ? Array(repeating: false, count: signature.parameterTypes.count)
                : signature.valueParameterIsVararg
            return (signature.parameterTypes.map { jvmErasedCallableType($0, types: types) }, flags)
        }
        let constructorKeys = constructors.map(erased)
        let hasConflict = symbols.lookupAll(fqName: classFQName).contains { id in
            guard let symbol = symbols.symbol(id), symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.expectDeclaration), !symbol.flags.contains(.actualDeclaration),
                  symbols.parentSymbol(for: id) == nil, isUserSource(id),
                  let signature = symbols.functionSignature(for: id),
                  signature.receiverType == nil, signature.contextReceiverTypes.isEmpty
            else { return false }
            let key = erased(signature)
            return constructorKeys.contains { $0.0 == key.0 && $0.1 == key.1 }
        }
        if hasConflict {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Conflicting declarations: class constructor and top-level function with the same signature.",
                range: range
            )
        }
    }

    func checkAndReportJVMErasedCallableConflict(
        for symbol: SymbolID,
        fqName: [InternedString],
        range: SourceRange?,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine
    ) {
        guard let newSymbol = symbols.symbol(symbol),
              newSymbol.kind == .function,
              let newSignature = symbols.functionSignature(for: symbol)
        else {
            return
        }

        let hasConflict = symbols.lookupAll(fqName: fqName).contains { existingID in
            guard existingID != symbol,
                  let existingSymbol = symbols.symbol(existingID),
                  existingSymbol.kind == newSymbol.kind,
                  !canCoexistAsExpectActualPair(newSymbol, existingSymbol),
                  !canCoexistAsSyntheticFallback(newSymbol, existingSymbol),
                  !canCoexistAsPrivateTopLevelCallableAcrossSourceFiles(
                      newSymbol,
                      existingSymbol,
                      symbols: symbols
                  ),
                  let existingSignature = symbols.functionSignature(for: existingID)
            else {
                return false
            }
            return hasSameJVMErasedCallableSignature(
                newSignature,
                existingSignature,
                types: types
            )
        }

        if hasConflict {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate JVM-erased callable declaration in the same package scope.",
                range: range
            )
        }
    }

    private func canCoexistAsPrivateTopLevelCallableAcrossSourceFiles(
        _ lhs: SemanticSymbol,
        _ rhs: SemanticSymbol,
        symbols: SymbolTable
    ) -> Bool {
        // Kotlin private top-level callables are file-scoped, so distinct source
        // files compile them into distinct JVM file facades.
        guard lhs.visibility == .private,
              rhs.visibility == .private,
              symbols.parentSymbol(for: lhs.id) == nil,
              symbols.parentSymbol(for: rhs.id) == nil,
              let lhsFileID = symbols.sourceFileID(for: lhs.id),
              let rhsFileID = symbols.sourceFileID(for: rhs.id)
        else {
            return false
        }
        return lhsFileID != rhsFileID
    }

    func hasSameJVMErasedCallableSignature(
        _ lhs: FunctionSignature,
        _ rhs: FunctionSignature,
        types: TypeSystem
    ) -> Bool {
        let lhsReceiver = lhs.receiverType.map { jvmErasedCallableType($0, types: types) }
        let rhsReceiver = rhs.receiverType.map { jvmErasedCallableType($0, types: types) }
        guard lhsReceiver == rhsReceiver,
              lhs.parameterTypes.count == rhs.parameterTypes.count
        else {
            return false
        }

        let lhsVarargs = normalizedVarargFlags(lhs.valueParameterIsVararg, count: lhs.parameterTypes.count)
        let rhsVarargs = normalizedVarargFlags(rhs.valueParameterIsVararg, count: rhs.parameterTypes.count)
        guard lhsVarargs == rhsVarargs else {
            return false
        }

        let lhsParameters = lhs.parameterTypes.map { jvmErasedCallableType($0, types: types) }
        let rhsParameters = rhs.parameterTypes.map { jvmErasedCallableType($0, types: types) }
        return zip(lhsParameters, rhsParameters).allSatisfy(==)
    }

    private func normalizedVarargFlags(_ flags: [Bool], count: Int) -> [Bool] {
        flags.isEmpty ? Array(repeating: false, count: count) : flags
    }

    func jvmErasedCallableType(_ type: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: type) {
        case .stringStruct:
            return types.makeNonNullable(type)
        case .primitive:
            return type
        default:
            return types.makeNonNullable(type)
        }
    }

    func canCoexistAsExpectActualPair(_ lhs: SemanticSymbol, _ rhs: SemanticSymbol) -> Bool {
        guard lhs.kind == rhs.kind else {
            return false
        }

        let lhsIsExpect = lhs.flags.contains(.expectDeclaration)
        let lhsIsActual = lhs.flags.contains(.actualDeclaration)
        let rhsIsExpect = rhs.flags.contains(.expectDeclaration)
        let rhsIsActual = rhs.flags.contains(.actualDeclaration)

        guard lhsIsExpect != lhsIsActual,
              rhsIsExpect != rhsIsActual
        else {
            return false
        }

        return (lhsIsExpect && rhsIsActual) || (lhsIsActual && rhsIsExpect)
    }

    func canCoexistAsSyntheticFallback(_ lhs: SemanticSymbol, _ rhs: SemanticSymbol) -> Bool {
        lhs.flags.contains(.synthetic) != rhs.flags.contains(.synthetic)
    }
}
