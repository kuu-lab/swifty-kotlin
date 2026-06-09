/// KClass / KFunction reflection-aware member-call lowerings.
///
/// Covers `lowerClassRefPropertyAccess`, `lowerKClassReifiedTypeNameHint`,
/// `lowerKClassReflectMemberCall`, and `lowerKClassVarReflectMemberCall`.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    func lowerClassRefPropertyAccess(
        _: ExprID,
        classRefExprID _: ExprID,
        classRefReceiver _: ExprID?,
        classRefTargetType: TypeID,
        propertyName: String,
        ast _: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let nullableStringType = sema.types.makeNullable(stringType)

        // 1. Emit the type token.
        let tokenExpr: KIRExprID
        if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
            // Reified type parameter — look up the synthetic token symbol.
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
            tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
        } else {
            // Concrete type — encode the type token at compile time.
            let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
            tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        }

        // 2. Emit the name-hint string.
        let nameHintExpr: KIRExprID
        if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
            let internedName = interner.intern(name)
            nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
            instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
        } else {
            // No name available — pass 0 (null sentinel) so the runtime falls
            // back to token-based decoding.
            nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
        }

        // 3. Emit the runtime call.
        let runtimeFuncName = propertyName == "qualifiedName"
            ? "kk_type_token_qualified_name"
            : "kk_type_token_simple_name"
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nullableStringType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeFuncName),
            arguments: [tokenExpr, nameHintExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    // MARK: - REFL-005: KClass.isInstance / members / constructors Lowering

    func lowerKClassReifiedTypeNameHint(
        exprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let typeArg = sema.bindings.callBindings[exprID]?.substitutedTypeArguments.first
        let name = typeArg.flatMap { RuntimeTypeCheckToken.qualifiedName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.flatMap { RuntimeTypeCheckToken.simpleName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.map { sema.types.renderType($0) }
            ?? ""
        let internedName = interner.intern(name)
        let result = arena.appendExpr(.stringLiteral(internedName), type: sema.types.stringType)
        instructions.append(.constValue(result: result, value: .stringLiteral(internedName)))
        return result
    }

    /// Lowers `T::class.isInstance(value)`, `T::class.members`, `T::class.constructors`
    /// to runtime calls `kk_kclass_isInstance`, `kk_kclass_members`, `kk_kclass_constructors`.
    ///
    /// These functions operate on the KClass box, so we first create the KClass
    /// via `kk_kclass_create` and then call the appropriate runtime function.
    func lowerKClassReflectMemberCall(
        _ exprID: ExprID,
        classRefTargetType: TypeID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType

        // 1. Create the KClass box via kk_kclass_create.
        let tokenExpr: KIRExprID
        if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
            tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
        } else {
            let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
            tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        }

        let nameHintExpr: KIRExprID
        if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
            let internedName = interner.intern(name)
            nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
            instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
        } else {
            nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
        }

        let kClassFallback = sema.types.makeKClassType(argument: classRefTargetType)
        let kclassExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: kClassFallback)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kclass_create"),
            arguments: [tokenExpr, nameHintExpr],
            result: kclassExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // STDLIB-REFLECT-065: For annotation-related calls, ensure metadata and
        // annotations are registered even if the class was never instantiated.
        // STDLIB-REFLECT-067: The same applies to kind/modifier boolean queries
        // (isData/isSealed/isValue/isEnum/isInterface/isObject/isInner/
        // isCompanion/isFun + isAbstract) — they read the class's flag bits from
        // the metadata registry, so the metadata must be present even when the
        // class is never constructed.
        let memberNeedsMetadataRegistration =
            memberName == "annotations" || memberName == "findAnnotation"
            || memberName == "findAssociatedObject"
            || Self.metadataBackedBooleanMembers.contains(memberName)
        if memberNeedsMetadataRegistration {
            emitClassLiteralMetadataRegistration(
                classRefTargetType: classRefTargetType,
                typeTokenExpr: tokenExpr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        return lowerKClassRuntimeMemberCall(
            exprID,
            kclassExpr: kclassExpr,
            memberName: memberName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            castFallbackType: classRefTargetType,
            visibilityFallbackType: stringType,
            instructions: &instructions
        )
    }

    private func lowerKClassRuntimeMemberCall(
        _ exprID: ExprID,
        kclassExpr: KIRExprID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        castFallbackType: TypeID,
        visibilityFallbackType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let stringType = sema.types.stringType

        func lowerFirstArgumentOrNull() -> KIRExprID {
            guard let firstArg = args.first else {
                let valueExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: valueExpr, value: .intLiteral(0)))
                return valueExpr
            }
            return driver.lowerExpr(
                firstArg.expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        func emitRuntimeCall(
            callee: String,
            arguments: [KIRExprID],
            fallbackType: TypeID,
            canThrow: Bool = false
        ) -> KIRExprID {
            let resultType = sema.bindings.exprTypes[exprID] ?? fallbackType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(callee),
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
            return result
        }

        switch memberName {
        case "isInstance":
            return emitRuntimeCall(
                callee: "kk_kclass_isInstance",
                arguments: [kclassExpr, lowerFirstArgumentOrNull()],
                fallbackType: boolType
            )

        case "cast", "safeCast":
            let canThrow = memberName == "cast"
            return emitRuntimeCall(
                callee: canThrow ? "kk_kclass_cast" : "kk_kclass_safeCast",
                arguments: [kclassExpr, lowerFirstArgumentOrNull()],
                fallbackType: castFallbackType,
                canThrow: canThrow
            )

        case "members":
            return emitRuntimeCall(
                callee: "kk_kclass_members",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "constructors":
            return emitRuntimeCall(
                callee: "kk_kclass_constructors",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "primaryConstructor":
            return emitRuntimeCall(
                callee: "kk_kclass_primary_constructor",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "properties":
            return emitRuntimeCall(
                callee: "kk_kclass_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "memberProperties":
            return emitRuntimeCall(
                callee: "kk_kclass_member_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "declaredMemberProperties":
            return emitRuntimeCall(
                callee: "kk_kclass_declared_member_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "functions":
            return emitRuntimeCall(
                callee: "kk_kclass_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "memberFunctions":
            return emitRuntimeCall(
                callee: "kk_kclass_member_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "declaredMemberFunctions":
            return emitRuntimeCall(
                callee: "kk_kclass_declared_member_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "isFinal":
            return emitRuntimeCall(
                callee: "kk_kclass_is_final",
                arguments: [kclassExpr],
                fallbackType: boolType
            )

        case "isOpen":
            return emitRuntimeCall(
                callee: "kk_kclass_is_open",
                arguments: [kclassExpr],
                fallbackType: boolType
            )

        case "isAbstract":
            return emitRuntimeCall(
                callee: "kk_kclass_is_abstract",
                arguments: [kclassExpr],
                fallbackType: boolType
            )

        // STDLIB-REFLECT-067: KClass kind/modifier / type-kind introspection.
        case "isData":
            return emitRuntimeCall(callee: "kk_kclass_is_data", arguments: [kclassExpr], fallbackType: boolType)

        case "isSealed":
            return emitRuntimeCall(callee: "kk_kclass_is_sealed", arguments: [kclassExpr], fallbackType: boolType)

        case "isValue":
            return emitRuntimeCall(callee: "kk_kclass_is_value", arguments: [kclassExpr], fallbackType: boolType)

        case "isEnum":
            return emitRuntimeCall(callee: "kk_kclass_is_enum", arguments: [kclassExpr], fallbackType: boolType)

        case "isInterface":
            return emitRuntimeCall(callee: "kk_kclass_is_interface", arguments: [kclassExpr], fallbackType: boolType)

        case "isObject":
            return emitRuntimeCall(callee: "kk_kclass_is_object", arguments: [kclassExpr], fallbackType: boolType)

        case "isInner":
            return emitRuntimeCall(callee: "kk_kclass_is_inner", arguments: [kclassExpr], fallbackType: boolType)

        case "isCompanion":
            return emitRuntimeCall(callee: "kk_kclass_is_companion", arguments: [kclassExpr], fallbackType: boolType)

        case "isFun":
            return emitRuntimeCall(callee: "kk_kclass_is_fun", arguments: [kclassExpr], fallbackType: boolType)

        case "visibility":
            return emitRuntimeCall(
                callee: "kk_kclass_visibility",
                arguments: [kclassExpr],
                fallbackType: visibilityFallbackType
            )

        case "typeParameters":
            return emitRuntimeCall(
                callee: "kk_kclass_type_parameters",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "supertypes":
            return emitRuntimeCall(
                callee: "kk_kclass_supertypes",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "annotations":
            return emitRuntimeCall(
                callee: "kk_kclass_get_annotations",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "findAnnotation":
            let searchNameExpr: KIRExprID
            if let firstArg = args.first {
                searchNameExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                let emptyStr = interner.intern("")
                searchNameExpr = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
                instructions.append(.constValue(result: searchNameExpr, value: .stringLiteral(emptyStr)))
            }
            return emitRuntimeCall(
                callee: "kk_kclass_find_annotation",
                arguments: [kclassExpr, searchNameExpr],
                fallbackType: sema.types.anyType
            )

        case "findAssociatedObject":
            let keyNameExpr = lowerKClassReifiedTypeNameHint(
                exprID: exprID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return emitRuntimeCall(
                callee: "kk_kclass_find_associated_object",
                arguments: [kclassExpr, keyNameExpr],
                fallbackType: sema.types.makeNullable(sema.types.anyType)
            )

        default:
            let result = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: result, value: .intLiteral(0)))
            return result
        }
    }

    // MARK: - REFL-005: KClass variable receiver member calls

    /// Lowers `kclassVar.isInstance(value)`, `kclassVar.members`, `kclassVar.constructors`
    /// where the receiver is a local variable of type KClass<T>, not a direct `T::class` expression.
    /// The receiver variable already holds a KClass box, so we use it directly.
    func lowerKClassVarReflectMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Lower the receiver expression to get the KClass box.
        let kclassExpr = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        return lowerKClassRuntimeMemberCall(
            exprID,
            kclassExpr: kclassExpr,
            memberName: memberName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            castFallbackType: sema.types.anyType,
            visibilityFallbackType: sema.types.anyType,
            instructions: &instructions
        )
    }

    /// KClass boolean members whose value is read from the class's metadata flag
    /// bits (see `emitClassLiteralMetadataRegistration`). A class-literal query of
    /// any of these must register the metadata so the flag resolves even when the
    /// class is never constructed. `isFinal`/`isOpen` are intentionally excluded —
    /// their flag bits (8/9) are not populated by the registration path.
    static let metadataBackedBooleanMembers: Set<String> = [
        "isData", "isSealed", "isValue", "isInterface", "isObject",
        "isEnum", "isAbstract", "isInner", "isCompanion", "isFun",
    ]

    /// Emits the `kk_kclass_register_metadata` (+ data-class field and annotation)
    /// registration for a compile-time class literal, reusing the *already emitted*
    /// `typeTokenExpr` so the registered metadata is keyed by the exact same type
    /// token as the `kk_kclass_create` box. This is what lets later metadata-backed
    /// queries (`isData`/`isSealed`/`isValue`/…, annotations, …) resolve correctly
    /// even when the class is never constructed.
    ///
    /// No-op for non-nominal target types (built-ins, reified type parameters) —
    /// they carry no class symbol to describe.
    func emitClassLiteralMetadataRegistration(
        classRefTargetType: TypeID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case let .classType(classType) = sema.types.kind(of: classRefTargetType) else {
            return
        }
        let classSymbol = classType.classSymbol
        guard let symbol = sema.symbols.symbol(classSymbol) else {
            return
        }

        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let fqNameInterned = interner.intern(fqName)
        let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
        instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

        let simpleNameStr = interner.resolve(symbol.name)
        let simpleInterned = interner.intern(simpleNameStr)
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleInterned), type: intType)
        instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleInterned)))

        let supertypes = sema.symbols.directSupertypes(for: classSymbol)
        let superClassSymbol = supertypes.first(where: { sema.symbols.symbol($0)?.kind == .class })
        let supertypeNameExpr: KIRExprID
        if let superClassSymbol, let superSym = sema.symbols.symbol(superClassSymbol) {
            let superFq = superSym.fqName.map { interner.resolve($0) }.joined(separator: ".")
            let superIn = interner.intern(superFq)
            supertypeNameExpr = arena.appendExpr(.stringLiteral(superIn), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superIn)))
        } else {
            supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
        }

        var flags: Int64 = 0
        if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
        if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
        if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
        if symbol.kind == .interface { flags |= 1 << 3 }
        if symbol.kind == .object { flags |= 1 << 4 }
        if symbol.kind == .enumClass { flags |= 1 << 5 }
        if symbol.kind == .annotationClass { flags |= 1 << 6 }
        if symbol.flags.contains(.abstractType) { flags |= 1 << 7 }
        // STDLIB-REFLECT-067: bits 10-12 for inner / companion / funInterface.
        if symbol.flags.contains(.innerClass) { flags |= 1 << 10 }
        if symbol.flags.contains(.funInterface) { flags |= 1 << 12 }
        if symbol.kind == .object {
            let parentFQName = Array(symbol.fqName.dropLast())
            if let parentSymbol = sema.symbols.lookup(fqName: parentFQName),
               sema.symbols.companionObjectSymbol(for: parentSymbol) == classSymbol {
                flags |= 1 << 11
            }
        }
        let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
        instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

        let fieldCount: Int64 = sema.symbols.nominalLayout(for: classSymbol).map { Int64($0.instanceFieldCount) } ?? -1
        let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
        instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

        let memberCount: Int64 = sema.symbols.nominalLayout(for: classSymbol).map { Int64($0.instanceFieldCount + $0.vtableSize) } ?? -1
        let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
        instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

        let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { sema.symbols.symbol($0)?.kind == .constructor }.count)
        let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
        instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

        let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))

        let classID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: classSymbol,
            sema: sema,
            interner: interner
        )
        emitDataClassFieldRegistration(
            objectSymbol: classSymbol,
            classID: classID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        emitKClassAnnotationRegistration(
            objectSymbol: classSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    /// Returns `true` when `receiverType` is a `kotlin.reflect.KClass<…>` receiver,
    /// recognizing both internal representations:
    /// - the dedicated `.kClassType` (produced by `T::class`), and
    /// - a `.classType` wrapping the `KClass` interface symbol (produced by an
    ///   explicit `KClass<T>` type annotation or library import).
    ///
    /// This mirrors the Sema-side `kClassReceiverArgumentType` so that KClass
    /// member-call lowering fires for both forms. Without the `.classType` arm,
    /// reflection members invoked on a `val k: KClass<T>` variable fall through
    /// to a regular call and emit an undefined `_<member>` symbol at link time.
    func isKClassReceiverType(_ receiverType: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let nonNull = sema.types.makeNonNullable(receiverType)
        if case .kClassType = sema.types.kind(of: nonNull) {
            return true
        }
        guard case let .classType(classType) = sema.types.kind(of: nonNull),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        if let kClassSymbol = sema.types.kClassInterfaceSymbol, classType.classSymbol == kClassSymbol {
            return true
        }
        let kClassFQName = [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("KClass"),
        ]
        let kClassName = interner.intern("KClass")
        return symbol.fqName == kClassFQName
            || (symbol.name == kClassName && symbol.fqName.isEmpty)
    }
}
