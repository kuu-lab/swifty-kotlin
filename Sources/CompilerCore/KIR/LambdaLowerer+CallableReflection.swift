import Foundation

extension LambdaLowerer {
    func registerCallableReflection(
        value: KIRExprID,
        callableSymbol: SymbolID,
        callableName: InternedString,
        targetSymbol: SymbolID?,
        parameterTypes: [TypeID],
        returnType: TypeID,
        captures: [KIRExprID],
        receiverCount: Int,
        packedConstructorVarargs: Bool = false,
        setterSymbol: SymbolID? = nil,
        includeInvocation: Bool = true,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        func integer(_ value: Int) -> KIRExprID {
            let expr = arena.appendExpr(.intLiteral(Int64(value)), type: sema.types.intType)
            instructions.append(.constValue(result: expr, value: .intLiteral(Int64(value))))
            return expr
        }
        func string(_ text: String) -> KIRExprID {
            let name = interner.intern(text)
            let expr = arena.appendExpr(.stringLiteral(name), type: sema.types.stringType)
            instructions.append(.constValue(result: expr, value: .stringLiteral(name)))
            return expr
        }
        func list(_ elements: [KIRExprID]) -> KIRExprID {
            makeReflectionArgumentList(elements, sema: sema, arena: arena, interner: interner, instructions: &instructions)
        }
        let signature = targetSymbol.flatMap { sema.symbols.functionSignature(for: $0) }
        func parameters(_ types: [TypeID], isSetter: Bool = false) -> KIRExprID {
            var elements: [KIRExprID] = []
            for (index, type) in types.enumerated() {
                let valueIndex = index - receiverCount
                let parameterSymbol = valueIndex >= 0 && valueIndex < (signature?.valueParameterSymbols.count ?? 0)
                    ? signature?.valueParameterSymbols[valueIndex] : nil
                let name = isSetter && index == types.count - 1 ? "value"
                    : parameterSymbol.flatMap { sema.symbols.symbol($0) }.map { interner.resolve($0.name) }
                let optional = valueIndex >= 0 && valueIndex < (signature?.valueParameterHasDefaultValues.count ?? 0)
                    && signature?.valueParameterHasDefaultValues[valueIndex] == true
                // RuntimeKParameterFlags: bit0 = isOptional, bit1 = isVararg.
                let vararg = valueIndex >= 0 && valueIndex < (signature?.valueParameterIsVararg.count ?? 0)
                    && signature?.valueParameterIsVararg[valueIndex] == true
                let parameterFlags = (optional ? 1 : 0) | (vararg ? 2 : 0)
                let parameterKind = index < receiverCount
                    ? callableReceiverParameterKind(targetSymbol: targetSymbol, signature: signature, sema: sema)
                    : 2 // VALUE
                let reflectedType = callableReflectionParameterType(type, isVararg: vararg, sema: sema, interner: interner)
                let reflectedTypeName = vararg
                    ? callableReflectionTypeName(of: reflectedType, sema: sema, interner: interner)
                    : sema.types.displayName(of: type, symbols: sema.symbols, interner: interner)
                let args = [integer(index), name.map(string) ?? {
                    let null = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                    instructions.append(.constValue(result: null, value: .null))
                    return null
                }(), string(reflectedTypeName),
                integer(parameterFlags), integer(parameterKind),
                integer(Int(RuntimeTypeCheckToken.encode(type: reflectedType, sema: sema, interner: interner))),
                integer(Int((targetSymbol ?? callableSymbol).rawValue) * 2 + (isSetter ? 1 : 0) + 1)]
                let result = arena.appendTemporary(type: sema.types.anyType)
                instructions.append(.call(symbol: nil, callee: interner.intern("__kk_kparameter_create_typed"), arguments: args,
                                          result: result, canThrow: false, thrownResult: nil))
                elements.append(result)
            }
            return list(elements)
        }

        let captureTypes = captures.map { arena.exprType($0) ?? sema.types.anyType }
        let boxedCaptures = zip(captures, captureTypes).map { capture, type in
            boxValueForAnySlot(capture, sourceType: type, types: sema.types, symbols: sema.symbols,
                              interner: interner, arena: arena, requireNonNull: true, into: &instructions)
        }
        let environment = list(boxedCaptures)
        let invoker: KIRExprID
        if includeInvocation {
            invoker = callableReflectionInvoker(
                callableSymbol: callableSymbol, callableName: callableName, targetSymbol: targetSymbol,
                parameterTypes: parameterTypes, captureTypes: captureTypes, returnType: returnType,
                packedConstructorVarargs: packedConstructorVarargs,
                sema: sema, arena: arena, interner: interner
            )
            if let reference = arena.expr(invoker) {
                instructions.append(.constValue(result: invoker, value: reference))
            }
        } else {
            invoker = integer(0)
        }
        let parameterList = parameters(parameterTypes)
        var typeParameterValues: [KIRExprID] = []
        if let signature,
           let factory = sema.symbols.lookup(fqName: ["kotlin", "reflect", "callableTypeParameter"].map(interner.intern)) {
            for (index, typeParameter) in signature.typeParameterSymbols.enumerated() where index >= signature.classTypeParameterCount {
                guard let parameterInfo = sema.symbols.symbol(typeParameter) else { continue }
                let bounds = (index < signature.typeParameterUpperBoundsList.count ? signature.typeParameterUpperBoundsList[index] : [])
                var boundValues: [KIRExprID] = []
                for bound in bounds.isEmpty ? [sema.types.nullableAnyType] : bounds {
                    let boundType = arena.appendTemporary(type: sema.types.anyType)
                    let arguments = [integer(0), string(sema.types.displayName(of: bound, symbols: sema.symbols, interner: interner)),
                                     list([]), integer(sema.types.makeNonNullable(bound) != bound ? 1 : 0)]
                    instructions.append(.call(symbol: nil, callee: interner.intern("kk_typeof"), arguments: arguments,
                                              result: boundType, canThrow: false, thrownResult: nil))
                    boundValues.append(boundType)
                }
                let parameter = arena.appendTemporary(type: sema.symbols.functionSignature(for: factory)?.returnType)
                let arguments = [string(interner.resolve(parameterInfo.name)), list(boundValues), integer(0),
                                 integer(parameterInfo.flags.contains(.reifiedTypeParameter) ? 1 : 0)]
                instructions.append(.call(symbol: factory, callee: callableTargetName(for: factory, sema: sema, interner: interner),
                                          arguments: arguments, result: parameter, canThrow: true, thrownResult: nil))
                typeParameterValues.append(parameter)
            }
        }
        let typeParameterList = list(typeParameterValues)
        let info = targetSymbol.flatMap { sema.symbols.symbol($0) }
        var flags = info?.flags.contains(.abstractType) == true ? 4 : info?.flags.contains(.openType) == true ? 2 : 1
        if info?.flags.contains(.constValue) == true { flags |= 16 }
        if info?.flags.contains(.lateinitProperty) == true { flags |= 32 }
        let visibility: Int = switch info?.visibility ?? .public {
        case .public: 0
        case .protected: 1
        case .internal: 2
        case .private: 3
        }
        let setter: KIRExprID
        let setterParameters: KIRExprID
        if let setterSymbol {
            setter = callableReflectionInvoker(
                callableSymbol: setterSymbol, callableName: interner.intern("set"), targetSymbol: nil,
                parameterTypes: parameterTypes + [returnType], captureTypes: captureTypes, returnType: sema.types.unitType,
                sema: sema, arena: arena, interner: interner
            )
            if let reference = arena.expr(setter) {
                instructions.append(.constValue(result: setter, value: reference))
            }
            setterParameters = parameters(parameterTypes + [returnType], isSetter: true)
        } else {
            setter = integer(0)
            setterParameters = list([])
        }
        instructions.append(.call(
            symbol: nil, callee: interner.intern("__kk_kcallable_register"),
            arguments: [value, invoker, environment, parameterList, typeParameterList, integer(flags), integer(visibility), setter, setterParameters],
            result: nil, canThrow: false, thrownResult: nil
        ))
        if let targetSymbol {
            emitKClassAnnotationRegistration(
                objectSymbol: targetSymbol, typeTokenExpr: value, sema: sema,
                arena: arena, interner: interner, instructions: &instructions,
                registrationCallee: "__kk_kcallable_register_single_annotation",
                annotations: runtimeCallableAnnotations(for: targetSymbol, ast: ast, sema: sema, interner: interner)
            )
        }
    }

    /// Internal `RuntimeKParameterBox.kind` for a leading receiver slot:
    /// 0 = INSTANCE (dispatch receiver), 1 = EXTENSION_RECEIVER,
    /// 3 = CONTEXT. `FunctionSignature.receiverType` conflates explicit
    /// extension receivers with the owning-class dispatch receiver, so
    /// the declared owner is recovered from the target's FQ name:
    /// top-level extensions keep the package owner (KSP-INF-011
    /// reparenting only changes parentSymbol), while member functions
    /// resolve to a nominal owner. Member-extension callables cannot be
    /// referenced in Kotlin, so a single receiver slot suffices.
    private func callableReceiverParameterKind(
        targetSymbol: SymbolID?,
        signature: FunctionSignature?,
        sema: SemaModule
    ) -> Int {
        guard let targetSymbol, let info = sema.symbols.symbol(targetSymbol) else { return 0 }
        if let receiverType = signature?.receiverType,
           signature?.contextReceiverTypes.contains(receiverType) == true {
            return 3
        }
        if sema.symbols.extensionPropertyReceiverType(for: targetSymbol) != nil {
            return 1
        }
        if let ownerSymbol = sema.symbols.lookup(fqName: Array(info.fqName.dropLast())),
           let owner = sema.symbols.symbol(ownerSymbol),
           [.class, .interface, .object, .enumClass, .annotationClass].contains(owner.kind) {
            return 0
        }
        return 1
    }

    private func runtimeCallableAnnotations(
        for symbol: SymbolID, ast: ASTModule, sema: SemaModule, interner: StringInterner
    ) -> [MetadataAnnotationRecord] {
        let file = sema.symbols.sourceFileID(for: symbol).flatMap { ast.file(for: $0) }
        return sema.symbols.annotations(for: symbol).filter { annotation in
            let annotationSymbol = file.flatMap {
                resolveAnnotationSymbol(named: annotation.annotationFQName, in: $0, symbols: sema.symbols, interner: interner)
            } ?? sema.symbols.lookup(fqName: annotation.annotationFQName.split(separator: ".").map { interner.intern(String($0)) })
            guard let annotationSymbol else { return true }
            let annotationFile = sema.symbols.sourceFileID(for: annotationSymbol).flatMap { ast.file(for: $0) }
            let retention = sema.symbols.annotations(for: annotationSymbol).first { meta in
                if meta.annotationFQName == "kotlin.annotation.Retention" { return true }
                guard let annotationFile,
                      let metaSymbol = resolveAnnotationSymbol(named: meta.annotationFQName, in: annotationFile,
                                                               symbols: sema.symbols, interner: interner) else { return false }
                return sema.symbols.symbol(metaSymbol)?.fqName.map(interner.resolve) == ["kotlin", "annotation", "Retention"]
            }
            guard let argument = retention?.arguments.first else { return true }
            let value = argument.split(separator: "=", maxSplits: 1).last.map(String.init) ?? argument
            var entry = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").last.map(String.init)
            if let entryName = entry, let annotationFile,
               let imported = annotationFile.imports.first(where: {
                   $0.alias.map(interner.resolve) == entryName
                       && $0.path.dropLast().map(interner.resolve) == ["kotlin", "annotation", "AnnotationRetention"]
               }), let importedEntry = imported.path.last {
                entry = interner.resolve(importedEntry)
            }
            return entry != "SOURCE" && entry != "BINARY"
        }
    }

    private func callableReflectionInvoker(
        callableSymbol: SymbolID, callableName: InternedString, targetSymbol: SymbolID?,
        parameterTypes: [TypeID], captureTypes: [TypeID], returnType: TypeID,
        packedConstructorVarargs: Bool = false,
        sema: SemaModule, arena: KIRArena, interner: StringInterner
    ) -> KIRExprID {
        let name = interner.intern("kk_reflect_invoke_\(callableSymbol.rawValue)_\(arena.declarations.count)")
        let symbol = sema.symbols.define(kind: .function, name: name, fqName: [name], declSite: nil,
                                         visibility: .private, flags: [.synthetic])
        let params = ["environment", "arguments", "mask"].map { text -> KIRParameter in
            let paramName = interner.intern(text)
            let param = sema.symbols.define(kind: .valueParameter, name: paramName, fqName: [name, paramName],
                                           declSite: nil, visibility: .private, flags: [.synthetic])
            return KIRParameter(symbol: param, type: sema.types.intType)
        }
        var body: [KIRInstruction] = [.beginBlock]
        let refs = params.map { param -> KIRExprID in
            let expr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: expr, value: .symbolRef(param.symbol)))
            return expr
        }
        let signature = targetSymbol.flatMap { sema.symbols.functionSignature(for: $0) }
        func unpack(
            _ list: KIRExprID, types: [TypeID], constructorParameters: Bool = false
        ) -> [KIRExprID] {
            types.enumerated().map { index, type in
                let offset = arena.appendExpr(.intLiteral(Int64(index)), type: sema.types.intType)
                body.append(.constValue(result: offset, value: .intLiteral(Int64(index))))
                let raw = arena.appendTemporary(type: sema.types.anyType)
                body.append(.call(symbol: nil, callee: interner.intern("__kk_list_get"), arguments: [list, offset],
                                  result: raw, canThrow: true, thrownResult: nil))
                if constructorParameters, let signature,
                   signature.valueParameterIsVararg.indices.contains(index),
                   signature.valueParameterIsVararg[index] {
                    let storageType = driver.constructorParameterStorageType(
                        at: index, signature: signature, sema: sema, interner: interner
                    )
                    let packed = arena.appendTemporary(type: storageType)
                    if primitiveVarargArrayType(elementType: type, sema: sema, interner: interner) != nil {
                        // Reflection receives the whole primitive array, not a
                        // boxed scalar of the signature's element type.
                        body.append(.copy(from: raw, to: packed))
                    } else {
                        // Kotlin reflection accepts Array<out T>; the existing
                        // source constructor ABI consumes a packed List<T>.
                        body.append(.call(
                            symbol: nil, callee: interner.intern("__kk_array_toList"),
                            arguments: [raw], result: packed, canThrow: false, thrownResult: nil
                        ))
                    }
                    return packed
                }
                return normalizeHOFPrimitiveParameter(raw, type: type, sema: sema, arena: arena,
                                                       interner: interner, instructions: &body)
            }
        }
        let arguments = unpack(refs[0], types: captureTypes)
            + unpack(refs[1], types: parameterTypes, constructorParameters: packedConstructorVarargs)
        let result = arena.appendTemporary(type: returnType)
        if let targetSymbol, signature?.valueParameterHasDefaultValues.contains(true) == true,
           sema.symbols.symbol(targetSymbol)?.kind == .constructor,
           let wrapper = driver.ctx.pendingGeneratedCallableDeclIDs.compactMap({ declID -> KIRFunction? in
               guard case let .function(function) = arena.decl(declID), function.symbol == callableSymbol else { return nil }
               return function
           }).first {
            let constructorName = interner.intern(interner.resolve(name) + "_constructor")
            let constructorSymbol = sema.symbols.define(kind: .function, name: constructorName, fqName: [constructorName],
                                                        declSite: nil, visibility: .private, flags: [.synthetic])
            let targetName = callableTargetName(for: targetSymbol, sema: sema, interner: interner)
            var constructorBody = wrapper.body.map { instruction -> KIRInstruction in
                guard case let .call(calleeSymbol, _, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType) = instruction,
                      calleeSymbol == targetSymbol else { return instruction }
                return .call(symbol: driver.callSupportLowerer.defaultStubSymbol(for: targetSymbol),
                             callee: interner.intern(interner.resolve(targetName) + "$default"),
                             arguments: arguments + [refs[2]], result: result, canThrow: canThrow,
                             thrownResult: thrownResult, isSuperCall: isSuperCall, qualifiedSuperType: qualifiedSuperType)
            }
            constructorBody.insert(.constValue(result: refs[2], value: .symbolRef(params[2].symbol)), at: 1)
            driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
                symbol: constructorSymbol, name: constructorName, params: wrapper.params + [params[2]], returnType: wrapper.returnType,
                body: constructorBody, isSuspend: false, isInline: false))))
            body.append(.call(symbol: constructorSymbol, callee: constructorName, arguments: arguments + [refs[2]],
                              result: result, canThrow: true, thrownResult: nil))
        } else if let targetSymbol, signature?.valueParameterHasDefaultValues.contains(true) == true,
           sema.symbols.symbol(targetSymbol)?.kind != .constructor {
            let zero = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            body.append(.constValue(result: zero, value: .intLiteral(0)))
            let normal = driver.ctx.makeLoopLabel()
            let done = driver.ctx.makeLoopLabel()
            body.append(.jumpIfEqual(lhs: refs[2], rhs: zero, target: normal))
            let owner = driver.callSupportLowerer.defaultStubOwnerSymbol(for: targetSymbol, sema: sema)
            let targetName = callableTargetName(for: owner, sema: sema, interner: interner)
            body.append(.call(symbol: driver.callSupportLowerer.defaultStubSymbol(for: owner),
                              callee: interner.intern(interner.resolve(targetName) + "$default"),
                              arguments: arguments + [refs[2]], result: result, canThrow: true, thrownResult: nil))
            body.append(.jump(done))
            body.append(.label(normal))
            body.append(.call(symbol: callableSymbol, callee: callableName, arguments: arguments,
                              result: result, canThrow: true, thrownResult: nil))
            body.append(.label(done))
        } else {
            body.append(.call(symbol: callableSymbol, callee: callableName, arguments: arguments,
                              result: result, canThrow: true, thrownResult: nil))
        }
        let boxed: KIRExprID
        if case .unit = sema.types.kind(of: returnType) {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            body.append(.constValue(result: unit, value: .unit))
            boxed = emitNonThrowingCall(callee: interner.intern("kk_box_unit"), arg: unit,
                                       resultType: sema.types.anyType, arena: arena, into: &body)
        } else {
            boxed = boxValueForAnySlot(result, sourceType: returnType, types: sema.types, symbols: sema.symbols,
                                      interner: interner, arena: arena, requireNonNull: true, into: &body)
        }
        body.append(.returnValue(boxed))
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: name, params: params, returnType: sema.types.anyType,
            body: body, isSuspend: false, isInline: false
        ))))
        return arena.appendExpr(.symbolRef(symbol), type: sema.types.anyType)
    }
}

private func callableReflectionParameterType(
    _ elementType: TypeID,
    isVararg: Bool,
    sema: SemaModule,
    interner: StringInterner
) -> TypeID {
    guard isVararg else { return elementType }
    if let primitiveArray = primitiveVarargArrayType(elementType: elementType, sema: sema, interner: interner) {
        return primitiveArray
    }
    guard let arraySymbol = sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Array")]) else {
        return elementType
    }
    return sema.types.make(.classType(ClassType(classSymbol: arraySymbol, args: [.out(elementType)])))
}

/// Renders callable parameter metadata with the fully-qualified type notation used by KType.
private func callableReflectionTypeName(
    of type: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> String {
    func nullabilitySuffix(_ nullability: Nullability) -> String {
        nullability == .nullable ? "?" : ""
    }

    func typeArgumentName(_ argument: TypeArg) -> String {
        switch argument {
        case let .invariant(type):
            callableReflectionTypeName(of: type, sema: sema, interner: interner)
        case let .out(type):
            "out \(callableReflectionTypeName(of: type, sema: sema, interner: interner))"
        case let .in(type):
            "in \(callableReflectionTypeName(of: type, sema: sema, interner: interner))"
        case .star:
            "*"
        }
    }

    switch sema.types.kind(of: type) {
    case .error:
        return "<error>"
    case .unit:
        return "kotlin.Unit"
    case .nullableUnit:
        return "kotlin.Unit?"
    case let .nothing(nullability):
        return "kotlin.Nothing\(nullabilitySuffix(nullability))"
    case let .any(nullability):
        return "kotlin.Any\(nullabilitySuffix(nullability))"
    case let .stringStruct(nullability):
        return "kotlin.String\(nullabilitySuffix(nullability))"
    case let .primitive(primitive, nullability):
        return "kotlin.\(primitive.kotlinName)\(nullabilitySuffix(nullability))"
    case let .classType(classType):
        let className = sema.symbols.symbol(classType.classSymbol)
            .map { $0.fqName.map(interner.resolve).joined(separator: ".") }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? sema.types.displayName(of: type, symbols: sema.symbols, interner: interner)
        let arguments = classType.args.isEmpty
            ? ""
            : "<" + classType.args.map(typeArgumentName).joined(separator: ", ") + ">"
        return "\(className)\(arguments)\(nullabilitySuffix(classType.nullability))"
    case let .typeParam(typeParameter):
        let name = sema.symbols.symbol(typeParameter.symbol).map { interner.resolve($0.name) } ?? "T"
        return "\(name)\(nullabilitySuffix(typeParameter.nullability))"
    case let .functionType(functionType):
        let contextPrefix = functionType.contextReceivers.isEmpty
            ? ""
            : "context(" + functionType.contextReceivers
                .map { callableReflectionTypeName(of: $0, sema: sema, interner: interner) }
                .joined(separator: ", ") + ") "
        let receiverPrefix = functionType.receiver
            .map { "\(callableReflectionTypeName(of: $0, sema: sema, interner: interner))." } ?? ""
        let suspendPrefix = functionType.isSuspend ? "suspend " : ""
        let parameters = functionType.params
            .map { callableReflectionTypeName(of: $0, sema: sema, interner: interner) }
            .joined(separator: ", ")
        let returnType = callableReflectionTypeName(of: functionType.returnType, sema: sema, interner: interner)
        let functionName = "\(contextPrefix)\(suspendPrefix)\(receiverPrefix)(\(parameters)) -> \(returnType)"
        return functionType.nullability == .nullable ? "(\(functionName))?" : functionName
    case let .intersection(types):
        return types
            .map { callableReflectionTypeName(of: $0, sema: sema, interner: interner) }
            .joined(separator: " & ")
    case let .kClassType(kClassType):
        let argument = callableReflectionTypeName(of: kClassType.argument, sema: sema, interner: interner)
        return "kotlin.reflect.KClass<\(argument)>\(nullabilitySuffix(kClassType.nullability))"
    }
}
