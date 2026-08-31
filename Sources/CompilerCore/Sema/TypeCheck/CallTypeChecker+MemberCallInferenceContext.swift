
extension CallTypeChecker {
    struct MemberCallInferenceRequest {
        let id: ExprID
        let receiverID: ExprID
        let calleeName: InternedString
        let args: [CallArgument]
        let range: SourceRange
        let ctx: TypeInferenceContext
        let expectedType: TypeID?
        let explicitTypeArgs: [TypeID]
        let safeCall: Bool
    }

    func markDeferredCollectionHOFLambdaIfNeeded(_ request: MemberCallInferenceRequest) {
        let ast = request.ctx.ast
        let sema = request.ctx.sema
        let interner = request.ctx.interner
        let calleeName = request.calleeName
        let args = request.args

        if ["firstNotNullOf", "firstNotNullOfOrNull", "takeLastWhile"]
            .contains(interner.resolve(calleeName)),
            args.count == 1,
            let lambdaExpr = ast.arena.expr(args[0].expr),
            lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
        }
    }

    func tryInferMemberCallWithoutReceiverSpecials(
        _ request: MemberCallInferenceRequest,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let explicitTypeArgs = request.explicitTypeArgs

        if let result = tryInferLateinitIsInitializedCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferClassRefMemberCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            explicitTypeArgs: explicitTypeArgs, range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferNumericCompanionMemberCall(
            id, receiverID: receiverID, calleeName: calleeName, args: args,
            ctx: ctx, locals: &locals
        ) {
            return result
        }

        return nil
    }

    /// FQN package-qualified top-level function call: e.g. kotlin.math.abs(x).
    /// Fires before receiver inference to avoid SEMA-0022 on unresolvable package identifiers.
    func tryInferFQNPackageTopLevelCall(
        _ request: MemberCallInferenceRequest,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let explicitTypeArgs = request.explicitTypeArgs
        let sema = ctx.sema
        let ast = ctx.ast
        let interner = ctx.interner

        guard let receiverPath = qualifiedCalleePath(for: receiverID, ast: ast),
              !receiverPath.isEmpty,
              locals[receiverPath[0]] == nil
        else { return nil }

        // A receiver path that itself names a declared class/interface/object/
        // enum (e.g. a singleton `object`, or a class with a companion) is a
        // type-qualified member access, not a package-qualified top-level
        // function reference like `kotlin.math.abs`. Its member functions
        // happen to be registered under the same owner-FQName + member-name
        // scheme as genuine top-level functions, so without this check a call
        // like `SomeObject.update(x) { ... }` would be misidentified as an FQN
        // top-level call below, which infers every argument eagerly and
        // leaves trailing lambda parameters without an expected type. Bail
        // out here so the regular member-call path (which defers lambda
        // inference until overload resolution picks a signature) handles it.
        if let receiverSymbolID = sema.symbols.lookup(fqName: receiverPath),
           let receiverSymbol = ctx.cachedSymbol(receiverSymbolID)
        {
            switch receiverSymbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                return nil
            default:
                break
            }
        }

        let fqnPath = receiverPath + [calleeName]
        var fqnCandidates = sema.symbols.lookupAll(fqName: fqnPath).filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind == .function || symbol.kind == .constructor
        }
        if fqnCandidates.isEmpty {
            // fqnPath may itself name a class rather than a top-level function
            // (e.g. `kotlin.text.StringBuilder` in `kotlin.text.StringBuilder()`,
            // or `kotlin.Pair` in `kotlin.Pair(1, 2)`): the class's own
            // declaration symbol lives at fqnPath, while its constructor(s)
            // live one level deeper at fqnPath + ["<init>"] (see
            // HeaderCollection's constructor registration). Mirrors the
            // unqualified-name constructor fallback in CallTypeChecker.swift,
            // minus `.object`: a singleton `object` is never callable as
            // `Obj()` in real Kotlin (verified against kotlinc), unlike a
            // bare class/enum-class/annotation-class reference.
            guard let classSymbolID = sema.symbols.lookup(fqName: fqnPath),
                  let classSymbol = ctx.cachedSymbol(classSymbolID)
            else { return nil }
            switch classSymbol.kind {
            case .class, .enumClass, .annotationClass:
                break
            default:
                return nil
            }
            // `Owner.AnnotationClass` and `Owner.AnnotationClass()` share the
            // same zero-arg `.memberCall` shape, but the AST arena records whether
            // parentheses were written. Only the parenthesis-less form can be a
            // bare type qualifier for further nested access (for example,
            // `RequiresOptIn.Level`); an explicit call must continue through
            // constructor resolution.
            if args.isEmpty,
               !ast.arena.isExplicitCall(id),
               classSymbol.kind == .annotationClass
            {
                let classifierType = sema.types.make(.classType(ClassType(
                    classSymbol: classSymbolID,
                    args: [],
                    nullability: .nonNull
                )))
                sema.bindings.bindIdentifier(id, symbol: classSymbolID)
                sema.bindings.bindExprType(id, type: classifierType)
                return classifierType
            }
            if classSymbol.flags.contains(.abstractType) {
                let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Cannot create an instance of abstract class '\(className)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let ctorFQName = fqnPath + [interner.intern("<init>")]
            fqnCandidates = sema.symbols.lookupAll(fqName: ctorFQName).filter { candidate in
                ctx.cachedSymbol(candidate)?.kind == .constructor
            }
            guard !fqnCandidates.isEmpty else { return nil }
        }

        let (vis, _) = ctx.filterByVisibility(fqnCandidates)
        guard !vis.isEmpty else { return nil }

        let argTypes = args.map { arg -> TypeID in
            sema.bindings.exprType(for: arg.expr) ?? driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
        }
        let callArgs = zip(args, argTypes).map { arg, type in
            CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: callArgs,
            explicitTypeArgs: explicitTypeArgs
        )
        let resolved = ctx.resolver.resolveCall(
            candidates: vis,
            call: call,
            expectedType: request.expectedType,
            ctx: sema
        )
        guard let chosen = resolved.chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosen)
        else { return nil }

        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        // The receiver chain (e.g. `kotlin.math`, `kotlin.text`) is a bare
        // namespace path, never type-checked above, so KIR lowering must not
        // treat it as a real value — see tryLowerFQNTopLevelResolvedCall.
        sema.bindings.markFQNTopLevelCallExpr(id)
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let resultType = sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }
}
