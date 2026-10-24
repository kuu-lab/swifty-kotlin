
extension CallLowerer {
    func lowerEmptyArrayCallExpr(
        chosenCallee: SymbolID?,
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let emptyArrayFQName = [interner.intern("kotlin"), interner.intern("emptyArray")]
        guard let chosenCallee,
              let symbol = sema.symbols.symbol(chosenCallee),
              symbol.kind == .function,
              symbol.fqName == emptyArrayFQName,
              sema.symbols.externalLinkName(for: chosenCallee) == "kk_empty_array",
              let arrayType = boundType,
              referenceArrayElementType(arrayType, sema: sema, interner: interner) != nil
        else {
            return nil
        }

        // kk_empty_array returns a fresh box today, but it carries no element
        // descriptor. Allocate at the typed call site so erased and reified
        // Array components can be attached before reflective callBy checks it.
        let zero = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zero, value: .intLiteral(0)))
        let array = arena.appendTemporary(type: arrayType)
        instructions.append(.call(
            callee: interner.intern("kk_array_new"),
            arguments: [zero],
            result: array,
            canThrow: false
        ))
        return appendRuntimeArrayComponentTag(
            array,
            arrayType: arrayType,
            context: driver.ctx,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func lowerArrayConstructorCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // Bundled source bodies are omitted from regular `kirDump`/library
        // output, so a source-backed primitive-array initializer can reach
        // this lowerer without a body to inline. Preserve its Sema binding
        // while reusing the compiler-provided array allocation and loop path.
        let isSourceBackedArrayInitializer: Bool = {
            guard args.count == 2,
                  sema.bindings.stdlibSpecialCallKind(for: exprID) == nil,
                  let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                  let symbol = sema.symbols.symbol(chosen),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(chosen),
                  symbol.fqName.count == 2,
                  symbol.fqName[0] == interner.intern("kotlin"),
                  let signature = sema.symbols.functionSignature(for: chosen),
                  signature.receiverType == nil,
                  signature.parameterTypes.count == args.count
            else {
                return false
            }
            let knownNames = KnownCompilerNames(interner: interner)
            return knownNames.isArrayLikeName(symbol.name)
                && ReceiverClassifier(sema: sema, interner: interner).isArrayLikeType(signature.returnType)
        }()
        guard (sema.bindings.stdlibSpecialCallKind(for: exprID) == .arrayConstructor
            || isSourceBackedArrayInitializer),
            args.count == 1 || args.count == 2
        else {
            return nil
        }

        let intType = sema.types.intType
        let boolType = sema.types.booleanType
        let anyType = sema.types.anyType
        let arrayNewCallee = interner.intern("kk_array_new_checked")
        let arrayTypeID = [
            sema.bindings.exprTypes[exprID],
            sema.bindings.callBinding(for: exprID)
                .flatMap { $0.chosenCallee }
                .flatMap { sema.symbols.functionSignature(for: $0)?.returnType },
        ].compactMap { runtimeArrayNominalTypeID($0, sema: sema, interner: interner) }.first

        let sizeIndex = args.firstIndex { $0.label == interner.intern("size") } ?? 0
        let initializerIndex = args.firstIndex { $0.label == interner.intern("init") } ?? 1
        // Evaluate supplied expressions once in their written order. A literal
        // lambda has no construction side effects and its body is inlined below.
        var evaluated: [Int: KIRExprID] = [:]
        for (index, argument) in args.enumerated() {
            if index == initializerIndex, case .lambdaLiteral = ast.arena.expr(argument.expr) { continue }
            evaluated[index] = driver.lowerExpr(argument.expr, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions)
        }
        guard let sizeExpr = evaluated[sizeIndex] else { return nil }

        // kk_array_new_checked throws NegativeArraySizeException for negative
        // sizes instead of silently clamping to an empty array.
        var arrayExpr = arena.appendTemporary(type: anyType)
        instructions.append(.call(
            callee: arrayNewCallee,
            arguments: [sizeExpr],
            result: arrayExpr,
            canThrow: true
        ))
        if let arrayTypeID {
            let typeIDExpr = arena.appendExpr(.intLiteral(arrayTypeID), type: intType)
            instructions.append(.constValue(result: typeIDExpr, value: .intLiteral(arrayTypeID)))
            let taggedArrayExpr = arena.appendTemporary(type: anyType)
            instructions.append(.call(
                callee: interner.intern("kk_array_tag_type"),
                arguments: [arrayExpr, typeIDExpr],
                result: taggedArrayExpr,
                canThrow: false
            ))
            arrayExpr = taggedArrayExpr
        }
        arrayExpr = appendRuntimeArrayComponentTag(
            arrayExpr, arrayType: sema.bindings.exprTypes[exprID], context: driver.ctx, sema: sema,
            arena: arena, interner: interner, instructions: &instructions
        )

        // Size-only primitive array constructor (e.g. ByteArray(8)): kk_array_new_checked
        // already zero-fills every slot (RuntimeValue(raw: 0)), which matches
        // Kotlin's per-type zero value (0, 0.0, false, NUL char) for every
        // primitive array element type, so there is no init lambda to run.
        guard args.count == 2 else {
            return arrayExpr
        }

        let arraySetCallee = interner.intern("kk_array_set")
        let lessThanCallee = interner.intern("kk_op_lt")
        let addCallee = interner.intern("kk_op_add")
        let unboxIntCallee = ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner)

        let indexExpr = arena.appendTemporary(type: intType)
        let oneExpr = arena.appendExpr(.intLiteral(1), type: intType)
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: indexExpr, value: .intLiteral(0)))
        instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let conditionLabel = driver.ctx.makeLoopLabel()
        let exitLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(conditionLabel))

        let conditionExpr = arena.appendTemporary(type: boolType)
        instructions.append(.call(
            callee: lessThanCallee,
            arguments: [indexExpr, sizeExpr],
            result: conditionExpr,
            canThrow: true
        ))
        instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: exitLabel))

        var lambdaResultExpr: KIRExprID?
        if let actionExprNode = ast.arena.expr(args[initializerIndex].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            let lambdaParamSymbol = driver.lambdaLowerer.syntheticLambdaParamSymbol(
                lambdaExprID: args[initializerIndex].expr,
                paramIndex: 0
            )
            let previousLocalValue = driver.ctx.localValue(for: lambdaParamSymbol)
            driver.ctx.setLocalValue(indexExpr, for: lambdaParamSymbol)
            let bodyResult = driver.lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            lambdaResultExpr = bodyResult
            if let previousLocalValue {
                driver.ctx.setLocalValue(previousLocalValue, for: lambdaParamSymbol)
            } else {
                driver.ctx.clearLocalValue(for: lambdaParamSymbol)
            }
        } else {
            guard let actionExpr = evaluated[initializerIndex] else { return nil }
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let actionResult = arena.appendTemporary(type: anyType)
                instructions.append(.call(
                    symbol: callableInfo.symbol,
                    callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments + [indexExpr],
                    result: actionResult,
                    canThrow: true
                ))
                lambdaResultExpr = actionResult
            }
        }

        if let lambdaResult = lambdaResultExpr {
            let setResult = arena.appendTemporary(type: anyType)
            instructions.append(.call(
                callee: arraySetCallee,
                arguments: [arrayExpr, indexExpr, lambdaResult],
                result: setResult,
                canThrow: false
            ))
        }

        let nextIndexBoxedExpr = arena.appendTemporary(type: intType)
        instructions.append(.call(
            callee: addCallee,
            arguments: [indexExpr, oneExpr],
            result: nextIndexBoxedExpr,
            canThrow: true
        ))
        let nextIndexExpr = emitNonThrowingCall(
            callee: unboxIntCallee,
            arg: nextIndexBoxedExpr,
            resultType: intType,
            arena: arena,
            into: &instructions
        )
        instructions.append(.copy(from: nextIndexExpr, to: indexExpr))
        instructions.append(.jump(conditionLabel))
        instructions.append(.label(exitLabel))

        return arrayExpr
    }
}
