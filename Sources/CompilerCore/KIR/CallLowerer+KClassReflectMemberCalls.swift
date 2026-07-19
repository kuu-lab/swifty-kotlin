/// KClass reflection-aware member-call lowerings for the members that remain
/// compiler special cases after KSP-496.
///
/// `simpleName`/`qualifiedName`/`isInstance`/`cast`/`safeCast`/the 12 boolean
/// class-kind flags/`members`/`constructors`/etc. now resolve as ordinary
/// Kotlin extension declarations
/// (Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt,
/// KClassMemberIntrospection.kt) through the normal member-call path.
///
/// `findAnnotation<T>()` / `findAssociatedObject<T>()` take a reified type
/// argument, which this compiler only supports via a small compiler-side
/// allowlist (like `typeOf<T>()`), so they remain here.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    // MARK: - REFL-005: KClass.findAnnotation / findAssociatedObject Lowering

    func lowerKClassReifiedTypeNameHint(
        exprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        lowerReifiedTypeNameHint(
            typeArg: sema.bindings.callBindings[exprID]?.substitutedTypeArguments.first,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    /// Renders a reified type argument (or `nil`) as a runtime name-hint string
    /// literal, preferring the fully-qualified name, then the simple name, then
    /// a rendered fallback, then an empty string when no type is available.
    func lowerReifiedTypeNameHint(
        typeArg: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let name = typeArg.flatMap { RuntimeTypeCheckToken.qualifiedName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.flatMap { RuntimeTypeCheckToken.simpleName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.map { sema.types.renderType($0) }
            ?? ""
        let internedName = interner.intern(name)
        let result = arena.appendExpr(.stringLiteral(internedName), type: sema.types.stringType)
        instructions.append(.constValue(result: result, value: .stringLiteral(internedName)))
        return result
    }

    /// Lowers `T::class.findAnnotation<A>()` / `T::class.findAssociatedObject<A>()`.
    ///
    /// These functions operate on the KClass box, so we first create the KClass
    /// via `__kk_kclass_create` and then call the appropriate runtime function.
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

        // 1. Create the KClass box via __kk_kclass_create.
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
        let kclassExpr = arena.appendTemporary(type: kClassFallback)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_kclass_create"),
            arguments: [tokenExpr, nameHintExpr],
            result: kclassExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // findAnnotation/findAssociatedObject read from the metadata registry,
        // so the metadata must be present even when the class is never
        // constructed.
        emitClassLiteralMetadataRegistration(
            classRefTargetType: classRefTargetType,
            typeTokenExpr: tokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
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
            castFallbackType: classRefTargetType,
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
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))

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
            let result = arena.appendTemporary(type: resultType)
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
        // KSP-496: cast/safeCast stay compiler special cases — see
        // KClassBasicAPI.kt for why (generic return-type inference gap).
        case "cast", "safeCast":
            let canThrow = memberName == "cast"
            return emitRuntimeCall(
                callee: canThrow ? "__kk_kclass_cast" : "__kk_kclass_safeCast",
                arguments: [kclassExpr, lowerFirstArgumentOrNull()],
                fallbackType: castFallbackType,
                canThrow: canThrow
            )

        case "findAnnotation":
            // STDLIB-REFLECT-065: findAnnotation<T>() is a reified intrinsic with
            // no value parameters — the annotation class to search for comes from
            // the reified `T` recorded in `findAnnotationSearchType(for:)` (see
            // `bindKClassFindAnnotationCall`), not from `args`.
            let searchNameExpr = lowerReifiedTypeNameHint(
                typeArg: sema.bindings.findAnnotationSearchType(for: exprID),
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return emitRuntimeCall(
                callee: "__kk_kclass_find_annotation",
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
                callee: "__kk_kclass_find_associated_object",
                arguments: [kclassExpr, keyNameExpr],
                fallbackType: sema.types.makeNullable(sema.types.anyType)
            )

        // KSP-496: kept as compiler special cases — see KClassMemberIntrospection.kt
        // for why (runtime handles aren't wired for genuine interface-conformance
        // checks, so casting them to their Kotlin-visible interface type throws).
        case "members":
            return emitRuntimeCall(
                callee: "__kk_kclass_members",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "constructors":
            return emitRuntimeCall(
                callee: "__kk_kclass_constructors",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "nestedClasses":
            return emitRuntimeCall(
                callee: "__kk_kclass_nested_classes",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "primaryConstructor":
            return emitRuntimeCall(
                callee: "__kk_kclass_primary_constructor",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "properties":
            return emitRuntimeCall(
                callee: "__kk_kclass_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "memberProperties":
            return emitRuntimeCall(
                callee: "__kk_kclass_member_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "declaredMemberProperties":
            return emitRuntimeCall(
                callee: "__kk_kclass_declared_member_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "functions":
            return emitRuntimeCall(
                callee: "__kk_kclass_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "memberFunctions":
            return emitRuntimeCall(
                callee: "__kk_kclass_member_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "declaredMemberFunctions":
            return emitRuntimeCall(
                callee: "__kk_kclass_declared_member_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "supertypes":
            return emitRuntimeCall(
                callee: "__kk_kclass_supertypes",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        default:
            let result = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: result, value: .intLiteral(0)))
            return result
        }
    }

    // MARK: - REFL-005: KClass variable receiver member calls

    /// Lowers `kclassVar.findAnnotation<A>()` / `kclassVar.findAssociatedObject<A>()`
    /// where the receiver is a local variable of type KClass<T>, not a direct
    /// `T::class` expression. The receiver variable already holds a KClass
    /// box, so we use it directly.
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
            instructions: &instructions
        )
    }

    /// Emits the `__kk_kclass_register_metadata` (+ data-class field and
    /// annotation) registration for a compile-time class literal, reusing the
    /// *already emitted* `typeTokenExpr` so the registered metadata is keyed
    /// by the exact same type token as the `__kk_kclass_create` box. This is
    /// what lets metadata-backed queries (the Kotlin-source `isData`/
    /// `isSealed`/`isValue`/…, `annotations`, `findAnnotation`,
    /// `findAssociatedObject`, …) resolve correctly even when the class is
    /// never constructed.
    ///
    /// No-op for non-nominal target types (built-ins, reified type
    /// parameters) — they carry no class symbol to describe.
    func emitClassLiteralMetadataRegistration(
        classRefTargetType: TypeID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard let classType = resolveClassType(classRefTargetType, sema: sema) else {
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

        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_kclass_register_metadata"),
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
        guard let (classType, symbol) = resolveClassTypeSymbol(nonNull, sema: sema) else {
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
