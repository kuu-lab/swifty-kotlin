
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
        let calleeStr: String
        let knownNames: KnownCompilerNames

        init(
            id: ExprID,
            receiverID: ExprID,
            calleeName: InternedString,
            args: [CallArgument],
            range: SourceRange,
            ctx: TypeInferenceContext,
            expectedType: TypeID?,
            explicitTypeArgs: [TypeID],
            safeCall: Bool
        ) {
            self.id = id
            self.receiverID = receiverID
            self.calleeName = calleeName
            self.args = args
            self.range = range
            self.ctx = ctx
            self.expectedType = expectedType
            self.explicitTypeArgs = explicitTypeArgs
            self.safeCall = safeCall
            self.calleeStr = ctx.interner.resolve(calleeName)
            self.knownNames = KnownCompilerNames(interner: ctx.interner)
        }

        var ast: ASTModule { ctx.ast }
        var sema: SemaModule { ctx.sema }
        var types: TypeSystem { ctx.sema.types }
        var symbols: SymbolTable { ctx.sema.symbols }
        var bindings: BindingTable { ctx.sema.bindings }
        var diagnostics: DiagnosticEngine { ctx.sema.diagnostics }
        var interner: StringInterner { ctx.interner }
        var isExplicitCall: Bool { ctx.ast.arena.isExplicitCall(id) }
        /// Member-property captures are shared by reads through one declared
        /// receiver, while same-typed declarations retain independent captures.
        var receiverDeclaration: SymbolID? {
            guard case .nameRef = ast.arena.expr(receiverID),
                  let symbol = bindings.identifierSymbol(for: receiverID)
            else {
                return nil
            }
            guard let kind = symbols.symbol(symbol)?.kind else { return nil }
            switch kind {
            case .local, .valueParameter, .property, .field:
                return symbol
            default:
                return nil
            }
        }
    }

    func markDeferredCollectionHOFLambdaIfNeeded(_ request: MemberCallInferenceRequest) {
        if ["firstNotNullOf", "firstNotNullOfOrNull", "takeLastWhile"].contains(request.calleeStr),
           request.args.count == 1,
           let lambdaExpr = request.ast.arena.expr(request.args[0].expr),
           lambdaExpr.isLambdaOrCallableRef
        {
            request.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
        }
    }

    func markRegexReplaceLambdaIfNeeded(
        chosenCallee: SymbolID,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) {
        guard ctx.sema.symbols.externalLinkName(for: chosenCallee) == "__kk_regex_replace_lambda",
              args.count == 2,
              let lambdaExpr = ctx.ast.arena.expr(args[1].expr),
              lambdaExpr.isLambdaOrCallableRef
        else {
            return
        }
        // KUU-600: Regex.replace invokes this transform through the native
        // collection-HOF callback ABI, which requires a closure-aware lambda
        // entry point even when the lambda does not capture values.
        ctx.sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
    }

    func tryInferMemberCallWithoutReceiverSpecials(
        _ request: MemberCallInferenceRequest,
        locals: inout LocalBindings
    ) -> TypeID? {
        if let result = tryInferLateinitIsInitializedCall(
            request.id, receiverID: request.receiverID, calleeName: request.calleeName, args: request.args,
            range: request.range, ctx: request.ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferClassRefMemberCall(
            request.id, receiverID: request.receiverID, calleeName: request.calleeName, args: request.args,
            explicitTypeArgs: request.explicitTypeArgs, range: request.range, ctx: request.ctx, locals: &locals
        ) {
            return result
        }

        if let result = tryInferNumericCompanionMemberCall(
            request.id, receiverID: request.receiverID, calleeName: request.calleeName, args: request.args,
            ctx: request.ctx, locals: &locals
        ) {
            return result
        }

        return nil
    }

    /// Resolves a property or classifier reached through a package-qualified
    /// path before receiver inference tries to interpret the leading package
    /// name as a value.
    func tryInferFQNQualifiedValue(
        _ request: MemberCallInferenceRequest,
        locals: LocalBindings
    ) -> TypeID? {
        guard request.args.isEmpty,
              request.explicitTypeArgs.isEmpty,
              !request.safeCall,
              !request.isExplicitCall,
              let receiverPath = qualifiedCalleePath(for: request.receiverID, ast: request.ast),
              !receiverPath.isEmpty,
              locals[receiverPath[0]] == nil
        else {
            return nil
        }

        let qualifiedPath = receiverPath + [request.calleeName]
        let propertyCandidates = request.symbols.lookupAll(fqName: qualifiedPath).filter { candidate in
            guard let symbol = request.ctx.cachedSymbol(candidate),
                  symbol.kind == .property,
                  request.symbols.extensionPropertyReceiverType(for: candidate) == nil
            else {
                return false
            }
            let parentKind = request.symbols.parentSymbol(for: candidate)
                .flatMap { request.symbols.symbol($0) }?.kind
            // A package-qualified object member such as
            // `kotlin.text.Charsets.UTF_8` has the object as its symbol
            // parent, even though the receiver path is still a namespace-only
            // FQN. Resolve it here so receiver inference does not treat the
            // leading `kotlin` segment as a runtime value. Keep source object
            // members on the regular receiver path so their object instance
            // and custom getter are preserved during lowering.
            let isStaticObjectProperty = parentKind == .object
                && (symbol.flags.contains(.synthetic) || symbol.flags.contains(.importedLibrary))
            return parentKind == nil || parentKind == .package || isStaticObjectProperty
        }
        if !propertyCandidates.isEmpty {
            let visibility = request.ctx.filterByVisibility(propertyCandidates, usageRange: request.range)
            guard let property = visibility.visible.first else {
                if let inaccessible = visibility.invisible.first {
                    driver.helpers.emitVisibilityError(
                        for: inaccessible,
                        name: request.calleeStr,
                        range: request.range,
                        diagnostics: request.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                return nil
            }
            guard let propertyType = request.symbols.propertyType(for: property) else {
                return nil
            }
            driver.helpers.checkDeprecation(
                for: property,
                sema: request.sema,
                interner: request.interner,
                range: request.range,
                diagnostics: request.diagnostics
            )
            driver.helpers.checkOptIn(
                for: property,
                ctx: request.ctx,
                range: request.range,
                diagnostics: request.diagnostics
            )
            request.bindings.bindIdentifier(request.id, symbol: property)
            if let propertySymbol = request.symbols.symbol(property),
               propertySymbol.flags.contains(.constValue),
               let constant = request.symbols.constValueExprKind(for: property)
            {
                request.bindings.bindConstExprValue(request.id, value: constant)
            }
            request.bindings.markFQNQualifiedValueExpr(request.id)
            request.bindings.bindExprType(request.id, type: propertyType)
            return propertyType
        }

        let receiverIsClassifier = request.symbols.lookupAll(fqName: receiverPath).contains { candidate in
            guard let symbol = request.ctx.cachedSymbol(candidate) else { return false }
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                return true
            default:
                return false
            }
        }
        guard let classifier = request.symbols.lookupAll(fqName: qualifiedPath).first(where: { candidate in
            guard let symbol = request.ctx.cachedSymbol(candidate) else { return false }
            switch symbol.kind {
            case .object, .annotationClass:
                return true
            case .class, .interface, .enumClass:
                return request.symbols.companionObjectSymbol(for: candidate) != nil
            default:
                return false
            }
        }),
            let classifierSymbol = request.ctx.cachedSymbol(classifier)
        else {
            return nil
        }
        if receiverIsClassifier {
            // A nested object reached through a package-qualified classifier
            // is a singleton value, even when the owner has no companion.
            // Preserve ordinary receiver inference for other classifier paths.
            guard classifierSymbol.kind == .object,
                  !request.ctx.cachedScopeLookup(receiverPath[0]).contains(where: {
                      guard let root = request.symbols.symbol($0) else { return false }
                      switch root.kind {
                      case .property, .object, .local, .valueParameter, .typeAlias, .enumClass:
                          return true
                      case .class, .interface, .annotationClass:
                          return request.symbols.companionObjectSymbol(for: root.id) != nil
                      default:
                          return false
                      }
                  }),
                  request.symbols.lookupAll(fqName: [receiverPath[0]]).contains(where: {
                      request.symbols.symbol($0)?.kind == .package
                  }) else { return nil }
            var owner = request.symbols.parentSymbol(for: classifier)
            while let current = owner, let info = request.symbols.symbol(current), info.kind != .package {
                guard request.ctx.visibilityChecker.isAccessible(info, fromFile: request.ctx.currentFileID,
                                                          enclosingClass: request.ctx.enclosingClassSymbol) else {
                    driver.helpers.emitVisibilityError(for: info, name: request.interner.resolve(info.name),
                                                       range: request.range, diagnostics: request.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                owner = request.symbols.parentSymbol(for: current)
            }
        }
        guard request.ctx.visibilityChecker.isAccessible(
            classifierSymbol,
            fromFile: request.ctx.currentFileID,
            enclosingClass: request.ctx.enclosingClassSymbol
        ) else {
            driver.helpers.emitVisibilityError(
                for: classifierSymbol,
                name: request.calleeStr,
                range: request.range,
                diagnostics: request.diagnostics
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }
        driver.helpers.checkDeprecation(
            for: classifier,
            sema: request.sema,
            interner: request.interner,
            range: request.range,
            diagnostics: request.diagnostics
        )
        driver.helpers.checkOptIn(
            for: classifier,
            ctx: request.ctx,
            range: request.range,
            diagnostics: request.diagnostics
        )
        let classifierType = request.types.make(.classType(ClassType(
            classSymbol: classifier,
            args: [],
            nullability: .nonNull
        )))
        request.bindings.bindIdentifier(request.id, symbol: classifier)
        request.bindings.markFQNQualifiedValueExpr(request.id)
        request.bindings.bindExprType(request.id, type: classifierType)
        return classifierType
    }

    /// Fires before receiver inference to avoid SEMA-0022 on unresolvable package identifiers.
    func tryInferFQNPackageTopLevelCall(
        _ request: MemberCallInferenceRequest,
        locals: inout LocalBindings
    ) -> TypeID? {

        guard let receiverPath = qualifiedCalleePath(for: request.receiverID, ast: request.ast),
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
        if request.sema.symbols.lookupAll(fqName: receiverPath).contains(where: { candidate in
            guard let symbol = request.ctx.cachedSymbol(candidate) else { return false }
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                return true
            default:
                return false
            }
        }) {
            return nil
        }

        let fqnPath = receiverPath + [request.calleeName]
        var fqnCandidates = request.sema.symbols.lookupAll(fqName: fqnPath).filter { candidate in
            guard let symbol = request.ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind == .function || symbol.kind == .constructor
        }
        if samConstructorTarget(named: request.calleeName, qualifiedName: fqnPath, ctx: request.ctx) != nil {
            var samFactoryCandidates: [SymbolID]?
            if let samType = inferSamConvertedCallExpr(
                request.id,
                calleeName: request.calleeName,
                qualifiedName: fqnPath,
                args: request.args,
                range: request.range,
                ctx: request.ctx,
                locals: &locals,
                expectedType: request.expectedType,
                explicitTypeArgs: request.explicitTypeArgs,
                samFactoryCandidates: &samFactoryCandidates
            ) {
                request.sema.bindings.markFQNTopLevelCallExpr(request.id)
                return samType
            }
            if let samFactoryCandidates {
                fqnCandidates = samFactoryCandidates
            }
        }
        if let classSymbolID = request.sema.symbols.lookupAll(fqName: fqnPath).first(where: {
            guard let symbol = request.ctx.cachedSymbol($0) else { return false }
            guard symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .annotationClass else {
                return false
            }
            return !symbol.flags.contains(.expectDeclaration)
                || request.sema.symbols.actualSymbol(for: $0) == nil
        }), let classSymbol = request.ctx.cachedSymbol(classSymbolID) {
            // Merge constructors with same-name factory functions, just as
            // unqualified call resolution does. fqnPath may name both a class
            // and a top-level function
            // (e.g. `kotlin.text.StringBuilder` in `kotlin.text.StringBuilder()`,
            // or `kotlin.Pair` in `kotlin.Pair(1, 2)`): the class's own
            // declaration symbol lives at fqnPath, while its constructor(s)
            // live one level deeper at fqnPath + ["<init>"] (see
            // HeaderCollection's constructor registration). Mirrors the
            // unqualified-name constructor merging in CallTypeChecker.swift,
            // minus `.object`: a singleton `object` is never callable as
            // `Obj()` in real Kotlin (verified against kotlinc), unlike a
            // bare class/enum-class/annotation-class reference.
            // A class qualifier and a zero-argument constructor call share the
            // same `.memberCall` shape. The AST arena records whether parentheses
            // were written, so a parenthesis-less class/enum/annotation reference
            // must remain a classifier for further nested access (for example,
            // `HexFormat.Builder`); an explicit call must continue through
            // constructor resolution.
            if request.args.isEmpty, !request.ast.arena.isExplicitCall(request.id) {
                let classifierType = request.sema.types.make(.classType(ClassType(
                    classSymbol: classSymbolID,
                    args: [],
                    nullability: .nonNull
                )))
                request.sema.bindings.bindIdentifier(request.id, symbol: classSymbolID)
                request.sema.bindings.bindExprType(request.id, type: classifierType)
                return classifierType
            }
            if classSymbol.flags.contains(.abstractType), fqnCandidates.isEmpty {
                let className = classSymbol.fqName.map { request.interner.resolve($0) }.joined(separator: ".")
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-ABSTRACT",
                    "Cannot create an instance of abstract class '\(className)'.",
                    range: request.range
                )
                request.sema.bindings.bindExprType(request.id, type: request.sema.types.errorType)
                return request.sema.types.errorType
            }
            let ctorFQName = fqnPath + [request.interner.intern("<init>")]
            if !classSymbol.flags.contains(.abstractType) {
                // Constructor symbols carry their declaring class as parent;
                // filter out the linked expect class's duplicate constructors.
                fqnCandidates.append(contentsOf: request.sema.symbols.lookupAll(fqName: ctorFQName).filter { candidate in
                    request.ctx.cachedSymbol(candidate)?.kind == .constructor
                        && request.sema.symbols.parentSymbol(for: candidate) == classSymbolID
                })
            }
        }

        // Imported aliases are expanded during regular call candidate
        // collection. Fully-qualified constructor calls need the same path so
        // an alias like `java.io.IOException` does not fall back to resolving
        // `java` as a value receiver.
        var typeAliasConstructor: TypeAliasConstructorContext?
        if fqnCandidates.isEmpty,
           let aliasID = request.sema.symbols.lookupAll(fqName: fqnPath).first(where: {
               request.ctx.cachedSymbol($0)?.kind == .typeAlias
           })
        {
            let aliasTypeParameters = request.sema.symbols.typeAliasTypeParameters(for: aliasID)
            if !request.explicitTypeArgs.isEmpty, request.explicitTypeArgs.count != aliasTypeParameters.count {
                request.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0062",
                    "Type argument count mismatch: expected \(aliasTypeParameters.count) but got \(request.explicitTypeArgs.count).",
                    range: request.range
                )
                request.sema.bindings.bindExprType(request.id, type: request.sema.types.errorType)
                return request.sema.types.errorType
            }

            let aliasTypeArgs: [TypeArg] = if request.explicitTypeArgs.isEmpty {
                aliasTypeParameters.map {
                    .invariant(request.sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
                }
            } else {
                request.explicitTypeArgs.enumerated().map { index, type in
                    let resolved = type == TypeID.invalid
                        ? request.sema.types.make(.typeParam(TypeParamType(
                            symbol: aliasTypeParameters[index],
                            nullability: .nonNull
                        )))
                        : type
                    return .invariant(resolved)
                }
            }

            if let expanded = driver.helpers.expandTypeAlias(
                aliasID,
                typeArgs: aliasTypeArgs,
                sema: request.sema,
                visited: [],
                depth: 0,
                diagnostics: request.sema.diagnostics
            ) {
                let aliasTarget: ClassType?
                switch request.sema.types.kind(of: expanded) {
                case let .classType(classType):
                    aliasTarget = classType
                case .any:
                    aliasTarget = request.sema.types.anyClassSymbol.map { ClassType(classSymbol: $0) }
                default:
                    aliasTarget = nil
                }

                if let aliasTarget {
                    let ownerID = request.sema.symbols.actualSymbol(for: aliasTarget.classSymbol) ?? aliasTarget.classSymbol
                    if let owner = request.ctx.cachedSymbol(ownerID) {
                        let constructorPath = owner.fqName + [request.interner.intern("<init>")]
                        let constructors = request.sema.symbols.lookupAll(fqName: constructorPath).filter {
                            request.ctx.cachedSymbol($0)?.kind == .constructor
                                && request.sema.symbols.parentSymbol(for: $0) == ownerID
                        }
                        if !constructors.isEmpty {
                            fqnCandidates.append(contentsOf: constructors)
                            let expandedConstructorType = request.sema.types.make(.classType(ClassType(
                                classSymbol: ownerID,
                                args: aliasTarget.args,
                                enclosingTypeArgs: aliasTarget.enclosingTypeArgs,
                                nullability: .nonNull
                            )))
                            typeAliasConstructor = TypeAliasConstructorContext(
                                typeParameterSymbols: aliasTypeParameters,
                                expandedType: expandedConstructorType,
                                typeAliasSymbol: aliasID
                            )
                        }
                    }
                }
            }
        }

        // Pass the use-site range so a covering @Suppress (expression or
        // declaration level) can expose bundled-internal declarations the
        // way unqualified calls do (KUU-3920: ktor-utils calls
        // `kotlinx.coroutines.internal.recoverStackTrace` by FQN).
        let (vis, _) = request.ctx.filterByVisibility(fqnCandidates, usageRange: request.range)
        guard !vis.isEmpty else { return nil }

        if request.sema.requiresResolvedLibraryCalls,
           receiverPath == KnownCompilerNames(interner: request.interner).kotlinSequencesPackage,
           ["sequence", "iterator"].contains(request.interner.resolve(request.calleeName)),
           vis.contains(where: { candidate in
               request.ctx.cachedSymbol(candidate)?.declSite.map { driver.sourceManager?.origin(of: $0.start.file) == .residualStdlib } == true
           }),
           let builder = inferSequenceBuilderCall(request.id, args: request.args, range: request.range, ctx: request.ctx, locals: &locals, expectedType: request.expectedType, explicitTypeArgs: request.explicitTypeArgs, calleeName: request.calleeName, jvmBuilderName: request.calleeName)
               ?? inferIteratorBuilderCall(request.id, args: request.args, range: request.range, ctx: request.ctx, locals: &locals, expectedType: request.expectedType, explicitTypeArgs: request.explicitTypeArgs, calleeName: request.calleeName, jvmBuilderName: request.calleeName) {
            request.sema.bindings.markFQNTopLevelCallExpr(request.id)
            return builder
        }
        if let builderResult = inferReceiverBuilderCall(
            request.id, calleeName: request.calleeName, args: request.args, range: request.range,
            ctx: request.ctx, locals: &locals, expectedType: request.expectedType,
            explicitTypeArgs: request.explicitTypeArgs, candidateOverride: vis
        ) {
            request.sema.bindings.markFQNTopLevelCallExpr(request.id)
            return builderResult
        }
        // A package qualifier is not a value receiver, but its arguments need
        // the same signature context as an imported top-level call. This also
        // contextualizes builders with explicit element type arguments.
        let argumentContextTypeArgs = typeAliasConstructor.map {
            aliasConstructorArgumentContextTypes($0, explicitTypeArgs: request.explicitTypeArgs, sema: request.sema)
        } ?? request.explicitTypeArgs
        var expectedTypeOverrides: [Int: TypeID] = [:]
        prepareCompareByExpectedTypeOverrides(
            args: request.args,
            callRange: request.range,
            candidates: vis,
            explicitTypeArgs: argumentContextTypeArgs,
            locals: locals,
            ctx: request.ctx,
            expectedTypeOverrides: &expectedTypeOverrides
        )
        let hasContextualIntegerLiteral = request.args.contains { argument in
            switch request.ast.arena.expr(argument.expr) {
            case .intLiteral, .uintLiteral:
                return true
            case let .unaryExpr(op, operand, _):
                guard op == .unaryPlus || op == .unaryMinus,
                      case .intLiteral = request.ast.arena.expr(operand)
                else {
                    return false
                }
                return true
            default:
                return false
            }
        }
        let needsArgumentPreparation = request.args.contains { request.ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }
            || !expectedTypeOverrides.isEmpty
            || hasContextualIntegerLiteral
        let preparedArgs = needsArgumentPreparation
            ? prepareCallArguments(
                args: request.args, callRange: request.range, candidates: vis,
                expectedTypeOverrides: expectedTypeOverrides,
                contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                    ? request.ctx.sema.types.unitType : request.expectedType,
                explicitTypeArgs: argumentContextTypeArgs, ctx: request.ctx, locals: &locals
            ) : nil
        let argTypes = preparedArgs?.argTypes ?? request.args.map { arg -> TypeID in
            request.sema.bindings.exprType(for: arg.expr) ?? driver.inferExpr(arg.expr, ctx: request.ctx, locals: &locals)
        }
        let callArgs = zip(request.args, argTypes).map { arg, type in
            CallArg.source(arg, type: type, callRange: request.range, ast: request.ctx.ast)
        }
        let call = CallExpr(
            range: request.range,
            calleeName: request.calleeName,
            args: callArgs,
            explicitTypeArgs: request.explicitTypeArgs,
            typeAliasConstructor: typeAliasConstructor,
            elvisLhsExpectedTypeHint: request.ctx.isElvisBranchExpectedTypeHint,
            elvisRhsCallResultTypeHint: request.ctx.elvisRhsCallResultTypeHint
        )
        let resolved: ResolvedCall
        if let preparedArgs {
            resolved = resolveCallRespectingLambdaReturnType(
                candidates: vis, args: request.args, argTypes: argTypes, range: request.range,
                calleeName: request.calleeName, explicitTypeArgs: request.explicitTypeArgs,
                typeAliasConstructor: typeAliasConstructor,
                expectedType: request.expectedType, implicitReceiverType: nil,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: request.ctx
            )
        } else {
            resolved = request.ctx.resolver.resolveCall(
                candidates: vis, call: call, expectedType: request.expectedType, ctx: request.sema
            )
        }
        guard let chosen = resolved.chosenCallee,
              let signature = request.sema.symbols.functionSignature(for: chosen)
        else { return nil }

        request.sema.bindings.bindCall(
            request.id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping
            )
        )
        request.sema.bindings.bindCallableTarget(request.id, target: .symbol(chosen))
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: request.sema,
            interner: request.interner,
            range: request.range,
            diagnostics: request.ctx.sema.diagnostics
        )
        markSourceBackedCoroutineLauncherArguments(chosen, args: request.args, ctx: request.ctx)
        // The receiver chain (e.g. `kotlin.math`, `kotlin.text`) is a bare
        // namespace path, never type-checked above, so KIR lowering must not
        // treat it as a real value — see tryLowerFQNTopLevelResolvedCall.
        request.sema.bindings.markFQNTopLevelCallExpr(request.id)
        // KSP-1323: fully-qualified `kotlin.reflect.typeOf<T>()` expands
        // through the same intrinsic as the unqualified spelling instead of
        // calling the bundled declaration body.
        if request.args.isEmpty,
           request.sema.wellKnownSymbols.reflectIntrinsic(for: chosen) == .typeOf
        {
            request.sema.bindings.markStdlibSpecialCallExpr(request.id, kind: .typeOf)
        }
        if request.args.isEmpty {
            switch request.sema.wellKnownSymbols.enumIntrinsic(for: chosen) {
            case .enumValues:
                request.sema.bindings.markStdlibSpecialCallExpr(request.id, kind: .enumValues)
                request.sema.bindings.markCollectionExpr(request.id)
            case .enumEntries:
                request.sema.bindings.markStdlibSpecialCallExpr(request.id, kind: .enumEntries)
            case .enumValueOf, .enumEntriesIntrinsic, .none:
                break
            }
        }
        let typeVarBySymbol = request.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let resultType = request.sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
        request.sema.bindings.bindExprType(request.id, type: resultType)
        return resultType
    }
}
