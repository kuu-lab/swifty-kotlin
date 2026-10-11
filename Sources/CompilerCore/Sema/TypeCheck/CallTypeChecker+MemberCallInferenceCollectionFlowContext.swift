extension CallTypeChecker {
    /// Extracted per-call shared state for `tryInferMemberCallCollectionFlowSpecials`.
    /// The `let` fields are the immutable call inputs and the receiver
    /// classification the original function computed up front; the `var`
    /// fields hold the mutable state the collection-HOF block kept in block
    /// scope. `collectionElementType`, `collectionMapTypes`, `listResultType`
    /// and `resultType` are assigned before first read inside
    /// `inferCollectionHOFSpecial`, matching the original
    /// definite-initialization ordering. `didReturnNil` records a
    /// `return nil` bail inside an extracted switch segment so the caller can
    /// stop dispatching exactly where the original function would have
    /// returned.
    final class MemberCallCollectionFlowContext {
        unowned let checker: CallTypeChecker
        let driver: TypeCheckDriver
        let id: ExprID
        let receiverID: ExprID
        let calleeName: InternedString
        let args: [CallArgument]
        let range: SourceRange
        let ctx: TypeInferenceContext
        let expectedType: TypeID?
        let explicitTypeArgs: [TypeID]
        let safeCall: Bool
        let ast: ASTModule
        let sema: SemaModule
        let interner: StringInterner
        let knownNames: KnownCompilerNames
        let receiverType: TypeID
        let receiverClassifier: ReceiverClassifier
        let receiverClassification: ReceiverClassification
        let isCollectionReceiver: Bool
        let isIterableReceiver: Bool
        let isArrayReceiver: Bool
        let isMapReceiver: Bool
        let isMutableListReceiver: Bool
        let isListReceiver: Bool
        let isListFactoryReceiver: Bool
        let isSyntheticSequenceReceiver: Bool
        let isSequenceReceiver: Bool
        let isSetReceiver: Bool
        let isEnumEntriesReceiver: Bool
        let isIterableIndexReceiver: Bool
        let isRangeReceiver: Bool
        let calleeStr: String
        let isIterableIndexFamilyHOF: Bool
        let isIterableFilterFamilyHOF: Bool
        let isCollectionHOF: Bool
        let isSourceBackedGenericOnEach: Bool
        let isIterableDropFamily: Bool

        // Always assigned before first read inside `inferCollectionHOFSpecial`
        // (matching the original `let` definite-initialization); the
        // `errorType` initial values are placeholders that are never observed.
        var collectionElementType: TypeID
        var collectionMapTypes: (key: TypeID, value: TypeID)
        var listResultType: TypeID
        var resultType: TypeID
        var sourceBackedSequenceAggregateTypeArguments: [TypeID]?
        var sourceBackedIterableAggregateTypeArguments: [TypeID]?
        var sourceBackedIterableAggregateMatchingParameterTypes: [TypeID]?
        var didReturnNil = false

        init(
            checker: CallTypeChecker,
            driver: TypeCheckDriver,
            id: ExprID,
            receiverID: ExprID,
            calleeName: InternedString,
            args: [CallArgument],
            range: SourceRange,
            ctx: TypeInferenceContext,
            expectedType: TypeID?,
            explicitTypeArgs: [TypeID],
            safeCall: Bool,
            ast: ASTModule,
            sema: SemaModule,
            interner: StringInterner,
            knownNames: KnownCompilerNames,
            receiverType: TypeID,
            receiverClassifier: ReceiverClassifier,
            receiverClassification: ReceiverClassification,
            isCollectionReceiver: Bool,
            isIterableReceiver: Bool,
            isArrayReceiver: Bool,
            isMapReceiver: Bool,
            isMutableListReceiver: Bool,
            isListReceiver: Bool,
            isListFactoryReceiver: Bool,
            isSyntheticSequenceReceiver: Bool,
            isSequenceReceiver: Bool,
            isSetReceiver: Bool,
            isEnumEntriesReceiver: Bool,
            isIterableIndexReceiver: Bool,
            isRangeReceiver: Bool,
            calleeStr: String,
            isIterableIndexFamilyHOF: Bool,
            isIterableFilterFamilyHOF: Bool,
            isCollectionHOF: Bool,
            isSourceBackedGenericOnEach: Bool,
            isIterableDropFamily: Bool
        ) {
            self.checker = checker
            self.driver = driver
            self.id = id
            self.receiverID = receiverID
            self.calleeName = calleeName
            self.args = args
            self.range = range
            self.ctx = ctx
            self.expectedType = expectedType
            self.explicitTypeArgs = explicitTypeArgs
            self.safeCall = safeCall
            self.ast = ast
            self.sema = sema
            self.interner = interner
            self.knownNames = knownNames
            self.receiverType = receiverType
            self.receiverClassifier = receiverClassifier
            self.receiverClassification = receiverClassification
            self.isCollectionReceiver = isCollectionReceiver
            self.isIterableReceiver = isIterableReceiver
            self.isArrayReceiver = isArrayReceiver
            self.isMapReceiver = isMapReceiver
            self.isMutableListReceiver = isMutableListReceiver
            self.isListReceiver = isListReceiver
            self.isListFactoryReceiver = isListFactoryReceiver
            self.isSyntheticSequenceReceiver = isSyntheticSequenceReceiver
            self.isSequenceReceiver = isSequenceReceiver
            self.isSetReceiver = isSetReceiver
            self.isEnumEntriesReceiver = isEnumEntriesReceiver
            self.isIterableIndexReceiver = isIterableIndexReceiver
            self.isRangeReceiver = isRangeReceiver
            self.calleeStr = calleeStr
            self.isIterableIndexFamilyHOF = isIterableIndexFamilyHOF
            self.isIterableFilterFamilyHOF = isIterableFilterFamilyHOF
            self.isCollectionHOF = isCollectionHOF
            self.isSourceBackedGenericOnEach = isSourceBackedGenericOnEach
            self.isIterableDropFamily = isIterableDropFamily
            collectionElementType = sema.types.errorType
            collectionMapTypes = (key: sema.types.errorType, value: sema.types.errorType)
            listResultType = sema.types.errorType
            resultType = sema.types.errorType
        }
    }
}

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func lookupStdlibSymbol(_ name: String, symbols: SymbolTable, interner: StringInterner) -> SymbolID? {
        checker.lookupStdlibSymbol(name, symbols: symbols, interner: interner)
    }

    func makeSyntheticSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        checker.makeSyntheticSequenceType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: elementType
        )
    }

    func getCollectionElementType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> TypeID {
        checker.getCollectionElementType(type, sema: sema, interner: interner)
    }

    func inferredLambdaReturnType(
        argExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID {
        checker.inferredLambdaReturnType(argExpr: argExpr, ast: ast, sema: sema)
    }

    func extractListElementType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        checker.extractListElementType(type, sema: sema, interner: interner)
    }

    func extractIterableOrSequenceElementType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        checker.extractIterableOrSequenceElementType(type, sema: sema, interner: interner)
    }

    func resolvedCollectionElementType(
        receiverID: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        checker.resolvedCollectionElementType(
            receiverID: receiverID,
            receiverType: receiverType,
            sema: sema,
            interner: interner,
            ctx: ctx,
            locals: &locals
        )
    }

    func typeContainsNothingType(_ type: TypeID, sema: SemaModule, depth: Int = 0) -> Bool {
        checker.typeContainsNothingType(type, sema: sema, depth: depth)
    }

    func isInferableNestedCallExpr(_ expr: ExprID, ast: ASTModule) -> Bool {
        checker.isInferableNestedCallExpr(expr, ast: ast)
    }

    func concreteNestedCallExpectedType(
        originalArgumentType: TypeID,
        boundType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        checker.concreteNestedCallExpectedType(
            originalArgumentType: originalArgumentType,
            boundType: boundType,
            sema: sema
        )
    }

    func bindCallAndResolveReturnType(
        _ id: ExprID,
        chosen: SymbolID,
        resolved: ResolvedCall,
        sema: SemaModule
    ) -> TypeID {
        checker.bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
    }

    func isCollectionLikeType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        checker.isCollectionLikeType(receiverType, sema: sema, interner: interner)
    }

    func extensionSyntheticFallbackReceiverMatches(
        callSiteReceiver: TypeID,
        declaredReceiver: TypeID,
        sema: SemaModule
    ) -> Bool {
        checker.extensionSyntheticFallbackReceiverMatches(
            callSiteReceiver: callSiteReceiver,
            declaredReceiver: declaredReceiver,
            sema: sema
        )
    }
}
