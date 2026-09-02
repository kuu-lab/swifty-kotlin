/// Inference for `prop::isInitialized` lateinit-property reference accesses.
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    /// Handles `prop::isInitialized` on lateinit property references.
    /// Returns the inferred type, or `nil` when the call is not a lateinit
    /// `isInitialized` access (the dispatcher should continue with other checks).
    func tryInferLateinitIsInitializedCall(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        guard args.isEmpty,
              calleeName == knownNames.isInitialized
        else {
            return nil
        }

        guard case .callableRef = ast.arena.expr(receiverID) else {
            _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
            guard let receiverType = sema.bindings.exprType(for: receiverID),
                  isKProperty0Receiver(receiverType, sema: sema, interner: interner)
            else {
                return nil
            }

            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-LATEINIT",
                "'isInitialized' is only available on property literals.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        if let propertySymbol = sema.bindings.identifierSymbol(for: receiverID),
           let propertyInfo = sema.symbols.symbol(propertySymbol),
           propertyInfo.kind == .property,
           propertyInfo.flags.contains(.lateinitProperty)
        {
            let boolType = sema.types.make(.primitive(.boolean, .nonNull))
            if let isInitializedProperty = ctx.cachedScopeLookup(calleeName).first(where: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .property
                else {
                    return false
                }
                return sema.symbols.extensionPropertyReceiverType(for: candidate) != nil
            }) {
                sema.bindings.bindIdentifier(id, symbol: isInitializedProperty)
            }
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }

        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-LATEINIT",
            "'isInitialized' is only available on lateinit property references.",
            range: range
        )
        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
    }

    private func isKProperty0Receiver(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let reflectPackage = [interner.intern("kotlin"), interner.intern("reflect")]
        let kProperty0Name = interner.intern("KProperty0")
        guard let kProperty0Symbol = sema.symbols.lookup(
            fqName: reflectPackage + [kProperty0Name]
        ) else {
            return false
        }
        let kProperty0StarType = sema.types.make(.classType(ClassType(
            classSymbol: kProperty0Symbol,
            args: [.star],
            nullability: .nonNull
        )))
        return sema.types.isSubtype(
            sema.types.makeNonNullable(receiverType),
            kProperty0StarType
        )
    }
}
