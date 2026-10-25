
struct CaptureAnalyzer {
    /// Same traversal as `collectCapturedOuterSymbols(in:...)`, but rooted at a
    /// function body (used for object-literal member functions, which have a
    /// `FunctionBody` rather than a single root `ExprID`). Each top-level
    /// statement is visited independently and the resulting capture sets are
    /// unioned, which is equivalent to visiting the whole body in one pass
    /// since the visitor carries no cross-statement state besides the
    /// accumulated capture set itself.
    func collectCapturedOuterSymbols(
        inBody body: FunctionBody,
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool = true
    ) -> [SymbolID] {
        guard !outerSymbols.isEmpty else {
            return []
        }
        let roots: [ExprID] = switch body {
        case let .block(exprs, _): exprs
        case let .expr(expr, _): [expr]
        case .unit: []
        }
        var captured: Set<SymbolID> = []
        for root in roots {
            captured.formUnion(collectCapturedOuterSymbols(
                in: root,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols,
                skipNestedClosures: skipNestedClosures
            ))
        }
        return captured.sorted(by: { $0.rawValue < $1.rawValue })
    }

    func collectCapturedOuterSymbols(
        in exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool = true
    ) -> [SymbolID] {
        collectCapturedOuterSymbolsImpl(
            ast: ast,
            sema: sema,
            outerSymbols: outerSymbols,
            skipNestedClosures: skipNestedClosures
        ) { visit, _ in
            visit(exprID)
        }
    }

    /// Same visitor rooted at a nominal declaration rather than an
    /// expression — for nominals nested inside an object literal, whose
    /// member bodies run as separate KIR functions and must contribute
    /// their outer references to the literal's capture set.
    func collectCapturedOuterSymbols(
        inDecl declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool = true
    ) -> [SymbolID] {
        collectCapturedOuterSymbolsImpl(
            ast: ast,
            sema: sema,
            outerSymbols: outerSymbols,
            skipNestedClosures: skipNestedClosures
        ) { _, visitLocalNominalDecl in
            visitLocalNominalDecl(declID)
        }
    }

    private func collectCapturedOuterSymbolsImpl(
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool,
        visitRoot: ((ExprID) -> Void, (DeclID) -> Void) -> Void
    ) -> [SymbolID] {
        guard !outerSymbols.isEmpty else {
            return []
        }

        var captured: Set<SymbolID> = []
        func recordCapture(for targetExprID: ExprID) {
            guard let symbol = sema.bindings.identifierSymbol(for: targetExprID),
                  outerSymbols.contains(symbol)
            else {
                return
            }
            captured.insert(symbol)
        }

        func visitBody(_ body: FunctionBody) {
            switch body {
            case let .block(exprs, _):
                for expr in exprs {
                    visit(expr)
                }
            case let .expr(expr, _):
                visit(expr)
            case .unit:
                break
            }
        }

        /// KUU-555: a named local nominal's captured outer locals are
        /// stored into instance fields at its construction site —
        /// which runs in whatever enclosing scope contains this decl —
        /// so every body that can reference an outer local must be
        /// visited here or the enclosing closure won't capture it.
        /// The same applies to nominals nested inside an object literal:
        /// their members run as separate KIR functions reached through
        /// `$outer`/capture fields, so the literal must provide the values.
        func visitLocalNominalDecl(_ declID: DeclID) {
            guard let decl = ast.arena.decl(declID) else {
                return
            }
            if let owner = sema.bindings.declSymbol(for: declID) {
                captured.formUnion(sema.bindings.objectLiteralCaptureSymbols(for: owner).filter {
                    outerSymbols.contains($0)
                })
            }
            let constructorArgExprs: [ExprID]
            let memberFunctionDecls: [DeclID]
            let memberPropertyDecls: [DeclID]
            let initBlocks: [FunctionBody]
            switch decl {
            case let .objectDecl(objectDecl):
                constructorArgExprs = objectDecl.superTypeConstructorArgs.map(\.expr)
                memberFunctionDecls = objectDecl.memberFunctions
                memberPropertyDecls = objectDecl.memberProperties
                initBlocks = []
            case let .classDecl(classDecl):
                constructorArgExprs = classDecl.superTypeEntries
                    .flatMap(\.constructorArgs).map(\.expr)
                memberFunctionDecls = classDecl.memberFunctions
                memberPropertyDecls = classDecl.memberProperties
                initBlocks = classDecl.initBlocks + classDecl.enumEntries.flatMap(\.initBlocks)
            default:
                constructorArgExprs = []
                memberFunctionDecls = []
                memberPropertyDecls = []
                initBlocks = []
            }
            for argExpr in constructorArgExprs {
                visit(argExpr)
            }
            for memberFunctionID in memberFunctionDecls {
                guard let memberDecl = ast.arena.decl(memberFunctionID),
                      case let .funDecl(memberFunction) = memberDecl
                else {
                    continue
                }
                visitBody(memberFunction.body)
            }
            for propertyID in memberPropertyDecls {
                guard let propertyDecl = ast.arena.decl(propertyID),
                      case let .propertyDecl(property) = propertyDecl
                else {
                    continue
                }
                if let initializer = property.initializer {
                    visit(initializer)
                }
                for accessorBody in [property.getter?.body, property.setter?.body, property.delegateBody] {
                    if let accessorBody {
                        visitBody(accessorBody)
                    }
                }
            }
            for initBlock in initBlocks {
                visitBody(initBlock)
            }
        }

        // swiftlint:disable:next cyclomatic_complexity
        func visit(_ currentExprID: ExprID) {
            guard let expr = ast.arena.expr(currentExprID) else {
                return
            }
            switch expr {
            case .nameRef:
                recordCapture(for: currentExprID)
                if let receiverSymbol = sema.bindings.implicitReceiverOuterReceiver(for: currentExprID),
                   outerSymbols.contains(receiverSymbol)
                {
                    captured.insert(receiverSymbol)
                }
                // Enum-entry members are owned by the entry field in Sema but
                // dispatched on the enum instance at runtime. A member read
                // inside a nested object/lambda needs that enum instance as
                // the receiver, so capture the enum owner symbol itself.
                if let symbol = sema.bindings.identifierSymbol(for: currentExprID),
                   let entryField = sema.symbols.parentSymbol(for: symbol),
                   let field = sema.symbols.symbol(entryField),
                   let enumOwner = sema.symbols.enumOwnerSymbol(for: field),
                   outerSymbols.contains(enumOwner)
                {
                    captured.insert(enumOwner)
                }

            case let .forExpr(_, iterable, body, _, _):
                visit(iterable)
                visit(body)

            case let .whileExpr(condition, body, _, _):
                visit(condition)
                visit(body)

            case let .doWhileExpr(body, condition, _, _):
                visit(body)
                visit(condition)

            case let .localDecl(_, _, _, initializer, _, _, _):
                if let initializer {
                    visit(initializer)
                }

            case let .localAssign(_, value, _):
                // KSP-CAP-001: a bare write to an outer mutable property
                // (`counter = 1`, no accompanying read anywhere in the body)
                // must still register the symbol as captured, or
                // `capturesMutableOuterProperty` (ObjectLiteralInference.swift)
                // never fires and no outer-receiver capture slot is allocated --
                // the KIR write then falls back to the literal's own receiver.
                recordCapture(for: currentExprID)
                visit(value)

            case let .memberAssign(receiver, _, value, _),
                 let .safeMemberAssign(receiver, _, value, _):
                if let receiverSymbol = sema.bindings.callBinding(for: currentExprID)?.dispatchReceiverSymbol,
                   outerSymbols.contains(receiverSymbol)
                {
                    captured.insert(receiverSymbol)
                }
                visit(receiver)
                visit(value)

            case let .indexedAssign(receiver, indices, value, _):
                visit(receiver)
                for idx in indices {
                    visit(idx)
                }
                visit(value)

            case let .call(callee, _, args, _):
                var isLocalFunctionCall = false
                let callBinding = sema.bindings.callBinding(for: currentExprID)
                let calleeSymbol = callBinding?.chosenCallee
                    ?? sema.bindings.identifierSymbol(for: callee)
                captured.formUnion(callBinding?.contextParameterReceiverSymbols.compactMap { $0 }.filter {
                    outerSymbols.contains($0)
                } ?? [])
                if let calleeSymbol,
                   sema.symbols.symbol(calleeSymbol)?.flags.contains(.localFunction) == true
                {
                    isLocalFunctionCall = true
                    // Lifted local functions receive their free variables as
                    // leading call arguments. Preserve those dependencies in
                    // the enclosing nominal so constructor lambdas can
                    // forward the environment after the function is lifted.
                    captured.formUnion(sema.bindings.localFunctionCaptureSymbols(for: calleeSymbol).filter {
                        outerSymbols.contains($0)
                    })
                }
                // Local class/object constructor calls materialize the
                // nominal's captured fields in the caller. Forward those
                // dependencies when the construction happens in another
                // local nominal or deferred callable body.
                if let constructor = sema.bindings.callBinding(for: currentExprID)?.chosenCallee,
                   sema.symbols.symbol(constructor)?.kind == .constructor,
                   let owner = sema.symbols.parentSymbol(for: constructor)
                {
                    captured.formUnion(sema.bindings.objectLiteralCaptureSymbols(for: owner).filter {
                        outerSymbols.contains($0)
                    })
                }
                // A call that resolved on an outer implicit receiver needs the
                // enclosing `this` captured so the receiver value reaches the
                // member body's lowering.
                if let receiverSymbol = sema.bindings.implicitReceiverOuterReceiver(for: currentExprID),
                   outerSymbols.contains(receiverSymbol)
                {
                    captured.insert(receiverSymbol)
                }
                // Same for a member-extension call's extension receiver when
                // Sema picked it from an enclosing tower entry.
                if let receiverSymbol = sema.bindings.implicitExtensionReceiver(for: currentExprID),
                   outerSymbols.contains(receiverSymbol)
                {
                    captured.insert(receiverSymbol)
                }
                // A bare member call inside an object literal resolves to the
                // enclosing class's member symbol. Preserve that class's
                // implicit receiver as a capture so lowering can still pass
                // the original `this` after the literal becomes active.
                if let target = sema.bindings.callBinding(for: currentExprID)?.chosenCallee,
                   let owner = sema.symbols.parentSymbol(for: target),
                   outerSymbols.contains(owner)
                {
                    captured.insert(owner)
                }
                if !isLocalFunctionCall {
                    visit(callee)
                }
                for arg in args {
                    visit(arg.expr)
                }

            case let .memberCall(receiver, _, _, args, _):
                let callBinding = sema.bindings.callBinding(for: currentExprID)
                captured.formUnion(
                    callBinding?.contextParameterReceiverSymbols.compactMap { $0 }.filter {
                        outerSymbols.contains($0)
                    } ?? []
                )
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }
                // `recv.fn(args)` invoking a lexical function-typed `fn` binds
                // fn's symbol on the call expr itself (Sema synthesizes a
                // callee nameRef for `CallableValueCallBinding.extensionCallableExpr`
                // and re-binds it on `request.id` exactly so this pass can see
                // it). Without recording it, an outer `fn` is never captured
                // into object literals / local nominals and the invoke lowers
                // to a raw symbolRef of a parameter that is not in scope.
                if sema.bindings.callableValueCalls[currentExprID]?.extensionCallableExpr != nil {
                    recordCapture(for: currentExprID)
                }

            case let .indexedAccess(receiver, indices, _):
                visit(receiver)
                for idx in indices {
                    visit(idx)
                }

            case let .binary(_, lhs, rhs, _):
                visit(lhs)
                visit(rhs)

            case let .whenExpr(subject, branches, elseExpr, _):
                if let subject {
                    visit(subject)
                }
                for branch in branches {
                    for condition in branch.conditions {
                        visit(condition)
                    }
                    if let guardExpr = branch.guard_ {
                        visit(guardExpr)
                    }
                    visit(branch.body)
                }
                if let elseExpr {
                    visit(elseExpr)
                }

            case let .returnExpr(value, _, _):
                if let value {
                    visit(value)
                }

            case let .ifExpr(condition, thenExpr, elseExpr, _):
                visit(condition)
                visit(thenExpr)
                if let elseExpr {
                    visit(elseExpr)
                }

            case let .tryExpr(body, catchClauses, finallyExpr, _):
                visit(body)
                for catchClause in catchClauses {
                    visit(catchClause.body)
                }
                if let finallyExpr {
                    visit(finallyExpr)
                }

            case let .unaryExpr(_, operand, _):
                visit(operand)

            case let .isCheck(value, _, _, _):
                visit(value)

            case let .asCast(value, _, _, _):
                visit(value)

            case let .nullAssert(value, _):
                visit(value)

            case let .safeMemberCall(receiver, _, _, args, _):
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }
                // Same lexical function-typed callee as `.memberCall` above:
                // `recv?.fn(args)` binds fn's symbol on the call expr so this
                // pass can keep it as a capture.
                if sema.bindings.callableValueCalls[currentExprID]?.extensionCallableExpr != nil {
                    recordCapture(for: currentExprID)
                }

            case let .compoundAssign(_, _, value, _):
                recordCapture(for: currentExprID)
                visit(value)

            case let .indexedCompoundAssign(_, receiver, indices, value, _):
                visit(receiver)
                for idx in indices {
                    visit(idx)
                }
                visit(value)

            case let .memberCompoundAssign(_, receiver, _, value, _):
                visit(receiver)
                visit(value)

            case let .throwExpr(value, _):
                visit(value)

            case let .lambdaLiteral(_, body, _, _):
                if !skipNestedClosures {
                    visit(body)
                }

            case let .callableRef(receiver, _, _):
                if let binding = sema.bindings.callableReferenceBinding(for: currentExprID),
                   let signature = sema.symbols.functionSignature(for: binding.chosenCallee) {
                    for index in signature.reifiedTypeParameterIndices where index < binding.substitutedTypeArguments.count {
                        for symbol in outerSymbols where sema.symbols.symbol(symbol)?.flags.contains(.reifiedTypeParameter) == true
                            && sema.types.typeContainsTypeParam(binding.substitutedTypeArguments[index], symbol: symbol) {
                            captured.insert(symbol)
                        }
                    }
                }
                if let receiverSymbol = sema.bindings.implicitReceiverOuterReceiver(for: currentExprID),
                   outerSymbols.contains(receiverSymbol)
                {
                    captured.insert(receiverSymbol)
                }
                if let receiverSymbol = sema.bindings.implicitExtensionReceiver(for: currentExprID),
                   outerSymbols.contains(receiverSymbol)
                {
                    captured.insert(receiverSymbol)
                }
                if let receiver {
                    visit(receiver)
                }

            case let .localFunDecl(_, _, valueParams, _, body, _, _, _, _):
                if !skipNestedClosures {
                    visitBody(body)
                    // Parameter default expressions evaluate in the lifted
                    // function's scope at call time, so their free variables
                    // are captures of the nested function that enclosing
                    // bodies must supply (KUU-3182).
                    for valueParam in valueParams {
                        if let defaultValue = valueParam.defaultValue {
                            visit(defaultValue)
                        }
                    }
                }

            case let .blockExpr(statements, trailingExpr, _):
                for statement in statements {
                    visit(statement)
                }
                if let trailingExpr {
                    visit(trailingExpr)
                }

            case let .stringTemplate(parts, _):
                for part in parts {
                    if case let .expression(expr) = part {
                        visit(expr)
                    }
                }

            case let .inExpr(lhs, rhs, _),
                 let .notInExpr(lhs, rhs, _):
                visit(lhs)
                visit(rhs)

            case let .destructuringDecl(_, _, initializer, _):
                visit(initializer)

            case let .forDestructuringExpr(_, iterable, body, _, _):
                visit(iterable)
                visit(body)

            case .thisRef:
                // Qualified extension-receiver references such as
                // `this@describe` are bound to the receiver parameter symbol.
                recordCapture(for: currentExprID)

            case .nullLiteral, .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral,
                 .charLiteral, .boolLiteral, .stringLiteral,
                 .breakExpr, .continueExpr, .superRef:
                break

            case let .objectLiteral(_, declID, _):
                guard let declID,
                      let decl = ast.arena.decl(declID),
                      case let .objectDecl(objectDecl) = decl
                else {
                    break
                }
                // KSP-CAP-018: the superclass constructor call's arguments
                // (`object : Base(x) { ... }`) are lowered in the enclosing
                // function's context (ObjectLiteralLowerer.
                // emitObjectLiteralSuperConstructorCall), same as a member
                // property initializer below — an outer local referenced only
                // here must still be recorded as captured when the object
                // literal itself sits inside a lambda.
                for arg in objectDecl.superTypeConstructorArgs {
                    visit(arg.expr)
                }
                for delegateExpr in objectDecl.superTypeEntries.compactMap(\.delegateExpression) {
                    visit(delegateExpr)
                }
                for memberFunctionID in objectDecl.memberFunctions {
                    guard let memberDecl = ast.arena.decl(memberFunctionID),
                          case let .funDecl(memberFunction) = memberDecl
                    else {
                        continue
                    }
                    visitBody(memberFunction.body)
                }
                for propertyID in objectDecl.memberProperties {
                    guard let propertyDecl = ast.arena.decl(propertyID),
                          case let .propertyDecl(property) = propertyDecl,
                          let initializer = property.initializer
                    else {
                        continue
                    }
                    visit(initializer)
                }
                // Nested nominals (e.g. `inner class` inside an object
                // expression, which Kotlin/JVM permits) run as their own
                // KIR functions — references to enclosing receivers there
                // are reached through `$outer`/this literal's capture fields.
                for nestedDeclID in objectDecl.nestedClasses + objectDecl.nestedObjects {
                    visitLocalNominalDecl(nestedDeclID)
                }

            case let .localNominalDecl(declID, _):
                visitLocalNominalDecl(declID)
            }
        }

        visitRoot(visit, visitLocalNominalDecl)
        return capturesWithBackingFieldOwners(captured, sema: sema)
    }

    /// A backing-field reference captures its owning instance, not a copy of
    /// the field value. Top-level backing fields are global storage and need
    /// no closure capture at all.
    private func capturesWithBackingFieldOwners(
        _ capturedSymbols: Set<SymbolID>,
        sema: SemaModule
    ) -> [SymbolID] {
        var result = capturedSymbols
        for field in capturedSymbols where sema.symbols.symbol(field)?.kind == .backingField {
            result.remove(field)
            guard let owner = sema.symbols.parentSymbol(for: field),
                  let ownerKind = sema.symbols.symbol(owner)?.kind,
                  [.class, .object, .enumClass].contains(ownerKind)
            else {
                continue
            }
            result.insert(owner)
        }
        return result.sorted(by: { $0.rawValue < $1.rawValue })
    }
}
