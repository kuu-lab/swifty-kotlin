/// Specializes enumValues after nested inline calls have propagated type tokens.
final class ReifiedEnumValuesLoweringPass: LoweringPass {
    static let name = "ReifiedEnumValuesLowering"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .propertyLowered

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        module.arena.declarations.contains { declaration in
            guard case let .function(function) = declaration else { return false }
            return function.body.contains { instruction in
                guard case let .call(symbol?, _, arguments, _, _, _, _, _) = instruction else { return false }
                return arguments.count == 1 && ctx.sema?.wellKnownSymbols.enumIntrinsic(for: symbol) == .enumValues
            }
        }
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let sema = ctx.sema else {
            module.recordLowering(Self.name)
            return
        }
        let enumTypesByToken = Dictionary(uniqueKeysWithValues: sema.symbols.allSymbols().compactMap { symbol -> (Int64, TypeID)? in
            guard symbol.kind == .enumClass else { return nil }
            let type = sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
            return (RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: ctx.interner), type)
        })
        let pairFirst = ctx.interner.intern("__kk_pair_first")
        let captureLoad = ctx.interner.intern("kk_array_get_inbounds")
        module.arena.transformFunctions { function in
            var constants: [KIRExprID: Int64] = [:]
            var parameterTokens: Set<KIRExprID> = []
            var parameterCaptures: Set<KIRExprID> = []
            let parameterSymbols = Set(function.params.map(\.symbol))
            var body = KIRLoweringEmitContext()
            for (index, instruction) in function.body.enumerated() {
                body.currentSourceRange = index < function.instructionLocations.count ? function.instructionLocations[index] : nil
                if case let .constValue(result, .intLiteral(value)) = instruction {
                    constants[result] = value
                } else if case let .constValue(result, .symbolRef(symbol)) = instruction,
                          parameterSymbols.contains(symbol) {
                    parameterTokens.insert(result)
                    parameterCaptures.insert(result)
                } else if case let .copy(from, to) = instruction {
                    constants[to] = constants[from]
                    if parameterTokens.contains(from) { parameterTokens.insert(to) }
                    if parameterCaptures.contains(from) { parameterCaptures.insert(to) }
                } else if case let .call(nil, callee, arguments, result?, _, _, _, _) = instruction,
                          let capture = arguments.first,
                          parameterCaptures.contains(capture) {
                    // Reified captures hold (class token, array component token).
                    // HOF closures may first load that Pair from a packed environment.
                    if callee == captureLoad, arguments.count == 2 {
                        parameterCaptures.insert(result)
                    } else if callee == pairFirst, arguments.count == 1 {
                        parameterTokens.insert(result)
                    }
                }
                guard case let .call(symbol?, _, arguments, result?, _, _, _, _) = instruction,
                      sema.wellKnownSymbols.enumIntrinsic(for: symbol) == .enumValues,
                      arguments.count == 1 else {
                    body.append(instruction)
                    continue
                }
                let token = constants[arguments[0]] ?? {
                    if case let .intLiteral(value) = module.arena.expr(arguments[0]) { return value }
                    return nil
                }()
                if let token,
                   let enumType = enumTypesByToken[token],
                   case let .classType(classType) = sema.types.kind(of: enumType),
                   let nominalSymbol = sema.symbols.symbol(classType.classSymbol) {
                    var generated: [KIRInstruction] = []
                    let arrayType = sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Array")]).map {
                        sema.types.make(.classType(ClassType(classSymbol: $0, args: [.invariant(enumType)], nullability: .nonNull)))
                    } ?? sema.types.anyType
                    let values = emitEnumEntryCollection(
                        classType: classType, nominalSymbol: nominalSymbol, boundType: arrayType, runtimeCalleeName: "kk_enum_make_values_array",
                        sema: sema, arena: module.arena, interner: ctx.interner, instructions: &generated
                    )
                    for generatedInstruction in generated { body.append(generatedInstruction) }
                    body.append(.copy(from: values, to: result))
                    continue
                }
                if parameterTokens.contains(arguments[0]), !function.isInline {
                    body.append(.call(
                        callee: ctx.interner.intern("kk_enum_values_for_token"),
                        arguments: [arguments[0]],
                        result: result,
                        canThrow: false
                    ))
                    continue
                }
                if !parameterTokens.contains(arguments[0]) {
                    ctx.diagnostics.error(
                        "KSWIFTK-INL-0001",
                        "Reified enumValues requires a concrete enum type after inline expansion.",
                        range: body.currentSourceRange ?? function.sourceRange
                    )
                }
                body.append(instruction)
                continue
            }
            var updated = function
            updated.replaceBody(body)
            return updated
        }
        module.recordLowering(Self.name)
    }
}
