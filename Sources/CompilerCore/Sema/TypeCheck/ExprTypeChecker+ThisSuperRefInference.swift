
extension ExprTypeChecker {
    func inferSuperRefExpr(
        _ id: ExprID,
        interfaceQualifier: InternedString?,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0050",
                "'super' is not allowed outside of a class body.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard driver.isSuperReceiverExpression(id) else {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0057",
                "'super' cannot be a callee.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if interfaceQualifier == nil, label == nil,
           let entrySuperContext = ctx.enumEntrySuperContext,
           ctx.enclosingClassSymbol == entrySuperContext.ownerSymbol
        {
            sema.bindings.bindExprType(id, type: entrySuperContext.type)
            return entrySuperContext.type
        }
        let superReceiverType: TypeID
        if let label {
            guard let labeledReceiverType = ctx.resolveQualifiedThis(label: label),
                  let ownerSymbol = driver.helpers.nominalSymbol(of: labeledReceiverType, types: sema.types)
            else {
                let labelStr = ctx.interner.resolve(label)
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0053",
                    "Unresolved label '\(labelStr)' for qualified 'super'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            sema.bindings.bindIdentifier(
                id,
                symbol: ctx.resolveQualifiedThisReceiverSymbol(label: label) ?? ownerSymbol
            )
            superReceiverType = labeledReceiverType
        } else {
            superReceiverType = memberExtensionDispatchReceiverType(ctx) ?? receiverType
        }
        guard let classSymbol = driver.helpers.nominalSymbol(of: superReceiverType, types: sema.types) else {
            return emitNoSuperclass(id: id, range: range, ctx: ctx)
        }
        if interfaceQualifier == nil, label == nil,
           isEnumEntryMemberBody(classSymbol: classSymbol, ctx: ctx)
        {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        if let qualifier = interfaceQualifier {
            return resolveQualifiedSuper(
                id: id,
                qualifier: qualifier,
                classSymbol: classSymbol,
                receiverType: superReceiverType,
                range: range,
                ctx: ctx
            )
        }
        return resolveUnqualifiedSuper(
            id: id, classSymbol: classSymbol, receiverType: superReceiverType, range: range, ctx: ctx
        )
    }

    private func memberExtensionDispatchReceiverType(_ ctx: TypeInferenceContext) -> TypeID? {
        guard let owner = ctx.enclosingClassSymbol,
              let declaration = ctx.currentDeclSymbol,
              ctx.sema.symbols.parentSymbol(for: declaration) == owner,
              ctx.sema.symbols.functionSignature(for: declaration)?.receiverType != nil
        else {
            return nil
        }
        return ctx.implicitReceiverMemberLookupTypes().last { receiverType in
            driver.helpers.nominalSymbol(of: receiverType, types: ctx.sema.types) == owner
        }
    }

    private func isEnumEntryMemberBody(classSymbol: SymbolID, ctx: TypeInferenceContext) -> Bool {
        let symbols = ctx.sema.symbols
        guard ctx.enclosingClassSymbol == classSymbol,
              symbols.symbol(classSymbol)?.kind == .enumClass,
              let currentDeclSymbol = ctx.currentDeclSymbol,
              let entrySymbol = symbols.parentSymbol(for: currentDeclSymbol),
              symbols.symbol(entrySymbol)?.kind == .field,
              symbols.parentSymbol(for: entrySymbol) == classSymbol
        else {
            return false
        }
        return true
    }

    /// Only direct supertypes (interfaces and classes) are valid per Kotlin spec.
    private func resolveQualifiedSuper(
        id: ExprID,
        qualifier: InternedString,
        classSymbol: SymbolID,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let supertypes = sema.symbols.directSupertypes(for: classSymbol)
        for superID in supertypes {
            guard let superSym = ctx.cachedSymbol(superID) else { continue }
            let isValidKind = superSym.kind == .interface || superSym.kind == .class || superSym.kind == .enumClass
            if isValidKind, superSym.name == qualifier {
                let typeArgs: [TypeArg]
                if case let .classType(currentClass) = sema.types.kind(of: receiverType) {
                    typeArgs = sema.types.liftedNominalSupertypeArgs(
                        from: classSymbol, childArgs: currentClass.args, to: superID
                    ) ?? []
                } else {
                    typeArgs = []
                }
                let superType = sema.types.make(.classType(ClassType(classSymbol: superID, args: typeArgs)))
                sema.bindings.bindExprType(id, type: superType)
                return superType
            }
        }
        let qualifierStr = ctx.interner.resolve(qualifier)
        ctx.sema.diagnostics.error(
            "KSWIFTK-SEMA-0054",
            "No type '\(qualifierStr)' found in direct supertypes for qualified 'super'.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    private func resolveUnqualifiedSuper(
        id: ExprID,
        classSymbol: SymbolID,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let supertypes = sema.symbols.directSupertypes(for: classSymbol)
        let classSupertypes = supertypes.filter {
            let kind = ctx.cachedSymbol($0)?.kind
            return kind == .class || kind == .enumClass
        }
        if let superclass = classSupertypes.first {
            let superType = sema.types.make(.classType(ClassType(classSymbol: superclass)))
            sema.bindings.bindExprType(id, type: superType)
            return superType
        }
        let hasInterfaces = supertypes.contains { ctx.cachedSymbol($0)?.kind == .interface }
        if hasInterfaces {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        return emitNoSuperclass(id: id, range: range, ctx: ctx)
    }

    private func emitNoSuperclass(id: ExprID, range: SourceRange, ctx: TypeInferenceContext) -> TypeID {
        let sema = ctx.sema
        ctx.sema.diagnostics.error(
            "KSWIFTK-SEMA-0052",
            "Class has no superclass.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func inferThisRefExpr(
        _ id: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        // A labeled `this@Outer` addresses a receiver on the enclosing tower,
        // not the current `this`, so it must resolve even in contexts where no
        // implicit receiver is active — e.g. a local class's superclass
        // constructor arguments, which type-check with `implicitReceiverType`
        // nil but keep the enclosing receiver entries (KUU-3226).
        if let label {
            if let qualifiedType = ctx.resolveQualifiedThis(label: label) {
                // An outer receiver whose enclosing `this` is capturable (e.g.
                // the class around an object literal) binds to its receiver
                // parameter symbol so capture analysis stores it and KIR
                // reads the captured value instead of the innermost receiver.
                if let receiverSymbol = ctx.resolveQualifiedThisReceiverSymbol(label: label) {
                    sema.bindings.bindIdentifier(id, symbol: receiverSymbol)
                } else if let currentDeclSymbol = ctx.currentDeclSymbol,
                          let currentDecl = sema.symbols.symbol(currentDeclSymbol),
                          currentDecl.name == label,
                          sema.symbols.functionSignature(for: currentDeclSymbol)?.receiverType != nil
                {
                    // An extension function's receiver is also addressable by the
                    // function-name label (for example `this@describe`). Bind that
                    // reference to the same synthetic receiver symbol used by KIR
                    // so nested receiver lambdas capture the outer receiver rather
                    // than accidentally reading their own receiver.
                    sema.bindings.bindIdentifier(
                        id,
                        symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: currentDeclSymbol)
                    )
                }
                sema.bindings.bindExprType(id, type: qualifiedType)
                return qualifiedType
            }
            let labelStr = ctx.interner.resolve(label)
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0053",
                "Unresolved label '\(labelStr)' for qualified 'this'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0051",
                "'this' is not allowed in this context.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let thisLocal = locals[ctx.interner.intern("this")] {
            sema.bindings.bindIdentifier(id, symbol: thisLocal.symbol)
            sema.bindings.bindExprType(id, type: thisLocal.type)
            return thisLocal.type
        }
        sema.bindings.bindExprType(id, type: receiverType)
        return receiverType
    }
}
