extension DeclTypeChecker {
    /// Resolve construction in the declaration's lexical context, after headers.
    /// The producer owns the body, including private types and default values.
    func typeCheckAnnotationFactories(
        _ annotations: [AnnotationNode], symbol: SymbolID, ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        var records = sema.symbols.annotations(for: symbol)
        for annotation in annotations {
            guard let usageID = annotation.usageID,
                  let index = records.firstIndex(where: { $0.usageID == usageID }),
                  records[index].factorySymbol == nil,
                  records[index].annotationFQName != "kotlin.Metadata",
                  let annotationSymbol = sema.symbols.lookup(fqName: records[index].annotationFQName.split(separator: ".").map {
                      ctx.interner.intern(String($0))
                  }), sema.symbols.symbol(annotationSymbol)?.kind == .annotationClass,
                  var tokens = annotation.constructionTokens,
                  let first = tokens.first, let last = tokens.last
            else { continue }

            // Header-only compiler annotations do not have a callable constructor.
            let annotationFQName = sema.symbols.symbol(annotationSymbol)?.fqName ?? []
            let constructors = sema.symbols.lookupAll(fqName: annotationFQName + [ctx.interner.intern("<init>")])
                .compactMap { sema.symbols.symbol($0) }
            guard constructors.contains(where: {
                $0.declSite != nil || sema.symbols.externalLinkName(for: $0.id) != nil
            }) else { continue }

            if !tokens.contains(where: { $0.kind == .symbol(.lParen) }) {
                tokens.append(Token(kind: .symbol(.lParen), range: last.range))
                tokens.append(Token(kind: .symbol(.rParen), range: last.range))
            }
            let parser = BuildASTPhase.ExpressionParser(
                tokens: tokens, interner: ctx.interner, astArena: ctx.ast.arena, diagnostics: sema.diagnostics
            )
            parser.allowAnnotationArrayLiterals = true
            guard let construction = parser.parse() else { continue }
            let wasCheckingAnnotation = driver.isCheckingAnnotationConstruction
            driver.isCheckingAnnotationConstruction = true
            defer { driver.isCheckingAnnotationConstruction = wasCheckingAnnotation }
            var locals: LocalBindings = [:]
            if let constructor = constructors.first,
               let signature = sema.symbols.functionSignature(for: constructor.id) {
                let arguments: [CallArgument]
                switch ctx.ast.arena.expr(construction) {
                case let .call(_, _, args, _), let .memberCall(_, _, _, args, _): arguments = args
                default: arguments = []
                }
                for (argumentIndex, argument) in arguments.enumerated() {
                    guard case let .call(callee, _, _, _) = ctx.ast.arena.expr(argument.expr),
                          case let .nameRef(name, _) = ctx.ast.arena.expr(callee),
                          ctx.interner.resolve(name) == "$annotationArrayLiteral",
                          let parameterIndex = driver.callChecker.parameterIndexForCallArgument(
                              at: argumentIndex, label: argument.label, in: signature, sema: sema
                          ), let expectedType = driver.callChecker.contextualCallArgumentType(
                              argument, parameterIndex: parameterIndex, in: signature, ctx: ctx
                          ) else { continue }
                    _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals,
                                         expectedType: expectedType)
                }
            }
            var constructionContext = ctx.with(currentDeclSymbol: symbol)
            constructionContext.annotationOptInValidation = (
                owner: annotationSymbol, range: ctx.ast.arena.exprRange(construction),
                markers: sema.bindings.validatedAnnotationOptInMarkers[usageID] ?? []
            )
            _ = driver.inferExpr(construction, ctx: constructionContext, locals: &locals)
            guard sema.bindings.callBindings[construction] != nil else { continue }
            validateAnnotationArguments(construction, ctx: ctx)
            guard resolvedAnnotationRetention(records[index], symbols: sema.symbols, interner: ctx.interner) == .runtime
            else { continue }
            let name = ctx.interner.intern("$annotationFactory$\(symbol.rawValue)$\(index)")
            let factory = sema.symbols.define(
                kind: .function, name: name, fqName: [name], declSite: first.range,
                visibility: .private, flags: [.synthetic]
            )
            sema.symbols.setFunctionSignature(FunctionSignature(
                parameterTypes: [], returnType: sema.types.anyType, canThrow: true
            ), for: factory)
            sema.bindings.bindAnnotationFactory(factory, expression: construction)
            let record = records[index]
            records[index] = MetadataAnnotationRecord(
                annotationFQName: record.annotationFQName, arguments: record.arguments,
                useSiteTarget: record.useSiteTarget, retention: record.retention, usageID: usageID,
                factorySymbol: factory, factoryLinkName: record.factoryLinkName
            )
        }
        sema.symbols.setAnnotations(records, for: symbol)
    }

    func validateAnnotationDefaultValue(_ expression: ExprID, ctx: TypeInferenceContext) {
        pendingAnnotationConstants.append((expression, ctx, true))
    }

    func validatePendingAnnotationConstants() {
        // Forward const initializer bindings are available only after all bodies.
        for (expression, ctx, isDefault) in pendingAnnotationConstants {
            guard !isAnnotationConstant(expression, ctx: ctx, depth: 0) else { continue }
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST",
                isDefault ? "Annotation default values must be compile-time constants." : "Annotation arguments must be compile-time constants.",
                range: ctx.ast.arena.exprRange(expression)
            )
        }
        pendingAnnotationConstants.removeAll()
    }

    private func validateAnnotationArguments(_ construction: ExprID, ctx: TypeInferenceContext) {
        let arguments: [CallArgument]
        switch ctx.ast.arena.expr(construction) {
        case let .call(_, _, args, _), let .memberCall(_, _, _, args, _): arguments = args
        default: return
        }
        for argument in arguments { pendingAnnotationConstants.append((argument.expr, ctx, false)) }
    }

    private func isAnnotationConstant(_ id: ExprID, ctx: TypeInferenceContext, depth: Int) -> Bool {
        guard depth < 64, let expression = ctx.ast.arena.expr(id) else { return false }
        if annotationConstantEvaluator == nil {
            annotationConstantEvaluator = ConstPropertyEvaluator(ast: ctx.ast, sema: ctx.sema, interner: ctx.interner)
        }
        if annotationConstantEvaluator?.constantExpression(id) != nil { return true }
        func constant(_ id: ExprID) -> Bool { isAnnotationConstant(id, ctx: ctx, depth: depth + 1) }
        func constantSymbol() -> Bool {
            guard let symbolID = ctx.sema.bindings.identifierSymbols[id],
                  let symbol = ctx.sema.symbols.symbol(symbolID) else { return false }
            guard symbol.kind == .field,
                  let owner = ctx.sema.symbols.lookup(fqName: Array(symbol.fqName.dropLast())) else { return false }
            return ctx.sema.symbols.symbol(owner)?.kind == .enumClass
        }
        switch expression {
        case .nameRef: return constantSymbol()
        case let .callableRef(receiver, member, _):
            guard ctx.interner.resolve(member) == "class", let receiver,
                  let symbolID = ctx.sema.bindings.identifierSymbols[receiver],
                  let kind = ctx.sema.symbols.symbol(symbolID)?.kind else { return false }
            return [.class, .interface, .object, .enumClass, .annotationClass, .typeAlias].contains(kind)
        case let .call(_, _, arguments, _), let .memberCall(_, _, _, arguments, _):
            if arguments.isEmpty, constantSymbol() { return true }
            guard let binding = ctx.sema.bindings.callBindings[id],
                  let callee = ctx.sema.symbols.symbol(binding.chosenCallee) else { return false }
            let isArrayFactory = callee.fqName.count == 2
                && ctx.interner.resolve(callee.fqName[0]) == "kotlin"
                && KnownCompilerNames.arrayFactoryFunctionNames.contains(ctx.interner.resolve(callee.name))
            let isAnnotationConstructor = callee.kind == .constructor
                && ctx.sema.symbols.lookup(fqName: Array(callee.fqName.dropLast())).flatMap {
                    ctx.sema.symbols.symbol($0)?.kind
                } == .annotationClass
            return (isArrayFactory || isAnnotationConstructor) && arguments.allSatisfy { constant($0.expr) }
        default: return false
        }
    }
}
