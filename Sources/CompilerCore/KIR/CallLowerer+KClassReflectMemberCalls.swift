/// KClass reflection-aware member-call lowerings for the members that remain
/// compiler special cases after KSP-496.
///
/// `simpleName`/`qualifiedName`/`isInstance`/`cast`/`safeCast`/the 12 boolean
/// class-kind flags/`members`/etc. now resolve as ordinary
/// Kotlin extension declarations
/// (Sources/CompilerCore/Stdlib/kotlin/reflect/KClasses.kt)
/// through the normal member-call path.
///
/// `objectInstance` / `sealedSubclasses` / `constructors` are source-declared interface properties,
/// implemented by the native singleton and subclass registries.
///
/// `findAnnotation<T>()` / `findAssociatedObject<T>()` take a reified type
/// argument, which this compiler only supports via a small compiler-side
/// allowlist (like `typeOf<T>()`), so they remain here.
///
/// `properties` also remains here: unlike its `member`/`declaredMember`
/// siblings, it is not a real kotlin-stdlib name, and diff cases rely on
/// being able to freely shadow it with a real user-declared extension.
extension CallLowerer {

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

    func lowerKClassReflectMemberCall(
        _ exprID: ExprID,
        classRefTargetType: TypeID,
        memberName: String,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType

        let tokenExpr: KIRExprID
        if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
            if let capturedToken = driver.ctx.localValue(for: tokenSymbol) {
                tokenExpr = capturedToken
            } else {
                tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
            }
        } else {
            let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
            tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        }

        let nameHintExpr: KIRExprID
        if let name = RuntimeTypeCheckToken.qualifiedName(of: classRefTargetType, sema: sema, interner: interner)
            ?? RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
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
            callee: interner.intern("__kk_kclass_create"),
            arguments: [tokenExpr, nameHintExpr],
            result: kclassExpr,
            canThrow: false
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
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func lowerKClassRuntimeMemberCall(
        _ exprID: ExprID,
        kclassExpr: KIRExprID,
        memberName: String,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        func emitRuntimeCall(
            callee: String,
            arguments: [KIRExprID],
            fallbackType: TypeID,
            canThrow: Bool = false
        ) -> KIRExprID {
            let resultType = sema.bindings.exprTypes[exprID] ?? fallbackType
            let result = arena.appendTemporary(type: resultType)
            instructions.append(.call(callee: interner.intern(callee), arguments: arguments, result: result, canThrow: canThrow))
            return result
        }

        switch memberName {
        case "objectInstance":
            return emitRuntimeCall(
                callee: "__kk_kclass_object_instance", arguments: [kclassExpr],
                fallbackType: sema.types.makeNullable(sema.types.anyType), canThrow: true
            )
        case "sealedSubclasses":
            return emitRuntimeCall(
                callee: "__kk_kclass_sealed_subclasses", arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )
        case "constructors":
            return emitRuntimeCall(
                callee: "__kk_kclass_constructors", arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )
        case "findAnnotation":
            // STDLIB-REFLECT-065: findAnnotation<T>() is a reified intrinsic with
            // no value parameters — the annotation class to search for comes from
            // the reified `T` recorded in `findAnnotationSearchType(for:)` (see
            // the resolved CallBinding), not from the value-argument list.
            let searchType = sema.bindings.findAnnotationSearchType(for: exprID)
                .map { sema.types.makeNonNullable($0) }
            let token: KIRExprKind
            if let searchType, case let .typeParam(parameter) = sema.types.kind(of: searchType) {
                token = .symbolRef(SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: parameter.symbol))
            } else {
                token = .intLiteral(searchType.map {
                    RuntimeTypeCheckToken.encode(type: $0, sema: sema, interner: interner)
                } ?? 0)
            }
            let searchToken = arena.appendExpr(token, type: sema.types.intType)
            instructions.append(.constValue(result: searchToken, value: token))
            return emitRuntimeCall(
                callee: "__kk_kclass_find_annotation_typed",
                arguments: [kclassExpr, searchToken],
                fallbackType: sema.types.anyType, canThrow: true
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

        // KSP-496: `properties` stays a compiler special case — see the NOTE in
        // KClasses.kt for why.
        case "properties":
            return emitRuntimeCall(
                callee: "__kk_kclass_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        default:
            let result = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: result, value: .intLiteral(0)))
            return result
        }
    }

    /// Lowers `kclassVar.findAnnotation<A>()` / `kclassVar.findAssociatedObject<A>()`
    /// where the receiver is a local variable of type KClass<T>, not a direct
    /// `T::class` expression. The receiver variable already holds a KClass
    /// box, so we use it directly.
    func lowerKClassVarReflectMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        memberName: String,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
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
            sema: sema,
            arena: arena,
            interner: interner,
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
        if let classType = resolveClassType(classRefTargetType, sema: sema) {
            appendTypeAncestryRegistrations(
                rootSymbol: classType.classSymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        var visitedClassSymbols: Set<SymbolID> = []
        emitClassLiteralMetadataRegistrationImpl(
            classRefTargetType: classRefTargetType,
            typeTokenExpr: typeTokenExpr,
            visitedClassSymbols: &visitedClassSymbols,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    /// Recursive worker for `emitClassLiteralMetadataRegistration` carrying a
    /// visited set shared across the transitive supertype closure and the
    /// sealed-subclass walk so neither can re-emit or loop (e.g. a sealed
    /// parent reached as a supertype re-listing the child being registered).
    func emitClassLiteralMetadataRegistrationImpl(
        classRefTargetType: TypeID,
        typeTokenExpr: KIRExprID,
        visitedClassSymbols: inout Set<SymbolID>,
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
        guard let symbol = sema.symbols.symbol(classSymbol),
              visitedClassSymbols.insert(classSymbol).inserted else {
            return
        }

        let fqName = RuntimeTypeCheckToken.qualifiedName(of: classRefTargetType, sema: sema, interner: interner)
            ?? symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let fqNameInterned = interner.intern(fqName)
        let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
        instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

        let simpleNameStr = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner)
            ?? interner.resolve(symbol.name)
        let simpleInterned = interner.intern(simpleNameStr)
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleInterned), type: intType)
        instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleInterned)))

        let supertypeNameExpr: KIRExprID
        if let joined = kclassSupertypeDisplayNamesJoined(
            for: classSymbol, sema: sema, interner: interner
        ) {
            let superIn = interner.intern(joined)
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
        // Reflection reports Kotlin modality, not the internal inheritance flags.
        let isSealed = symbol.flags.contains(.sealedType)
        let isAbstract = !isSealed && (symbol.kind == .interface || symbol.kind == .annotationClass || symbol.flags.contains(.abstractType))
        if isAbstract { flags |= 1 << 7 }
        if !isSealed && !isAbstract && !symbol.flags.contains(.openType) { flags |= 1 << 8 }
        if !isSealed && !isAbstract && symbol.flags.contains(.openType) { flags |= 1 << 9 }
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
        let ownerKind = sema.symbols.parentSymbol(for: classSymbol)
            .flatMap { sema.symbols.symbol($0)?.kind }
        let isLocalOrAnonymous = symbol.fqName.contains { component in
            let name = interner.resolve(component)
            return name.hasPrefix("__localdecl_") || name.hasPrefix("__ObjectLiteral_")
        }
        if isLocalOrAnonymous
            || ownerKind.map({ [.function, .property, .local].contains($0) }) == true {
            flags |= 1 << 13
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
            callee: interner.intern("__kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false
        ))
        emitClassTypeParameterMetadataRegistration(
            for: classSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        emitClassEnclosingMetadataRegistration(
            for: classSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        emitKClassDisplayNameRegistration(
            symbol: classSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        emitKClassCastNameRegistration(
            symbol: classSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        emitKClassCompanionAndNestedRegistration(
            classSymbol: classSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )

        // KUU-1448: `KType.classifier` materializes KClass handles at runtime
        // from the supertype display names stored in this registration, and
        // resolves *their* metadata through the same token-keyed registry.
        // Register the transitive nominal-supertype closure so such a handle
        // answers `supertypes`/`isSubclassOf` even when the ancestor's own
        // `T::class` literal (or constructor) never ran.
        emitTransitiveSupertypeKClassMetadataRegistrations(
            for: classSymbol,
            visitedClassSymbols: &visitedClassSymbols,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        if symbol.flags.contains(.sealedType) {
            let subclasses = sema.symbols.sealedSubclasses(for: classSymbol)
                ?? sema.symbols.directSubtypes(of: classSymbol)
            for subclass in subclasses {
                let subclassType = sema.types.make(.classType(ClassType(
                    classSymbol: subclass, args: [], nullability: .nonNull
                )))
                let token = RuntimeTypeCheckToken.encode(type: subclassType, sema: sema, interner: interner)
                let tokenExpr = arena.appendExpr(.intLiteral(token), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .intLiteral(token)))
                emitClassLiteralMetadataRegistrationImpl(
                    classRefTargetType: subclassType, typeTokenExpr: tokenExpr,
                    visitedClassSymbols: &visitedClassSymbols,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
                let name = interner.intern(RuntimeTypeCheckToken.simpleName(of: subclassType, sema: sema, interner: interner) ?? "")
                let nameExpr = arena.appendExpr(.stringLiteral(name), type: sema.types.stringType)
                instructions.append(.constValue(result: nameExpr, value: .stringLiteral(name)))
                instructions.append(.call(
                    callee: interner.intern("__kk_kclass_register_sealed_subclass"),
                    arguments: [typeTokenExpr, tokenExpr, nameExpr],
                    result: arena.appendTemporary(type: intType), canThrow: false
                ))
            }
        }

        emitKClassAnnotationRegistration(
            objectSymbol: classSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        emitJavaClassDeclaredMethodsRegistration(
            for: classSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        emitJavaClassDeclaredFieldsRegistration(
            for: classSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    /// Registers Java-shaped method names from this class's own declarations.
    /// The runtime keys them by type token, so inherited members remain separate.
    private func emitJavaClassDeclaredMethodsRegistration(
        for classSymbol: SymbolID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let owner = sema.symbols.symbol(classSymbol) else { return }
        let intType = sema.types.intType
        let stringType = sema.types.stringType

        func javaTypeName(_ type: TypeID) -> String {
            switch sema.types.kind(of: type) {
            case .error, .any:
                return "java.lang.Object"
            case .unit, .platformUnit:
                return "void"
            case .nullableUnit:
                return "kotlin.Unit"
            case .nothing:
                return "java.lang.Void"
            case .stringStruct:
                return "java.lang.String"
            case let .primitive(primitive, _):
                switch primitive {
                case .boolean: return "boolean"
                case .char: return "char"
                case .int: return "int"
                case .long: return "long"
                case .float: return "float"
                case .double: return "double"
                case .byte: return "byte"
                case .short: return "short"
                case .uint: return "kotlin.UInt"
                case .ulong: return "kotlin.ULong"
                case .ubyte: return "kotlin.UByte"
                case .ushort: return "kotlin.UShort"
                }
            case let .classType(classType):
                guard let typeSymbol = sema.symbols.symbol(classType.classSymbol) else {
                    return "java.lang.Object"
                }
                let name = typeSymbol.fqName.map(interner.resolve).joined(separator: ".")
                return name == "kotlin.RuntimeException" ? "java.lang.RuntimeException" : name
            case .typeParam, .intersection:
                return "java.lang.Object"
            case let .functionType(functionType):
                let arity = functionType.contextReceivers.count
                    + (functionType.receiver == nil ? 0 : 1)
                    + functionType.params.count
                let prefix = functionType.isSuspend ? "kotlin.coroutines.SuspendFunction" : "kotlin.jvm.functions.Function"
                return "\(prefix)\(arity)"
            case .kClassType:
                return "kotlin.reflect.KClass"
            }
        }

        func descriptor(parameterTypes: [TypeID], returnType: TypeID) -> String {
            let parameterTokens = parameterTypes.map { type in
                let token = RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
                    & ~RuntimeTypeCheckToken.nullableFlag
                return String(token)
            }
            let returnToken = RuntimeTypeCheckToken.encode(type: returnType, sema: sema, interner: interner)
                & ~RuntimeTypeCheckToken.nullableFlag
            return "\(parameterTokens.joined(separator: ","))|\(returnToken)|\(javaTypeName(returnType))"
        }

        func register(name: String, signature: String, flags: Int64 = 0) {
            let internedName = interner.intern(name)
            let nameExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
            instructions.append(.constValue(result: nameExpr, value: .stringLiteral(internedName)))

            let internedSignature = interner.intern(signature)
            let signatureExpr = arena.appendExpr(.stringLiteral(internedSignature), type: stringType)
            instructions.append(.constValue(result: signatureExpr, value: .stringLiteral(internedSignature)))

            let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
            instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

            instructions.append(.call(
                callee: interner.intern("__kk_java_class_register_declared_method"),
                arguments: [typeTokenExpr, nameExpr, signatureExpr, flagsExpr],
                result: arena.appendTemporary(type: intType),
                canThrow: false
            ))
        }

        for childID in sema.symbols.children(ofFQName: owner.fqName) {
            guard let child = sema.symbols.symbol(childID) else { continue }
            switch child.kind {
            case .function:
                guard let signature = sema.symbols.functionSignature(for: childID) else { continue }
                let visibilityFlags: Int64 = child.visibility == .public || child.visibility == .internal ? 2 : 0
                register(
                    name: interner.resolve(child.name),
                    signature: descriptor(parameterTypes: signature.parameterTypes, returnType: signature.returnType),
                    flags: visibilityFlags
                )
            case .property:
                guard let propertyType = sema.symbols.propertyType(for: childID) else { continue }
                let visibilityFlags: Int64 = child.visibility == .public || child.visibility == .internal ? 2 : 0
                let propertyName = interner.resolve(child.name)
                let getterName: String
                if propertyName.hasPrefix("is"),
                   propertyName.dropFirst(2).first?.isUppercase == true
                {
                    getterName = propertyName
                } else if let first = propertyName.first {
                    getterName = "get" + String(first).uppercased() + propertyName.dropFirst()
                } else {
                    getterName = "get"
                }
                register(
                    name: getterName,
                    signature: descriptor(parameterTypes: [], returnType: propertyType),
                    flags: visibilityFlags
                )

                let hasRuntimePropertyAnnotation = sema.symbols.annotations(for: childID).contains { annotation in
                    annotation.useSiteTarget == nil
                        && resolvedAnnotationRetention(annotation, symbols: sema.symbols, interner: interner) != .source
                }
                if hasRuntimePropertyAnnotation {
                    register(
                        name: "\(getterName)$annotations",
                        signature: descriptor(parameterTypes: [], returnType: sema.types.unitType),
                        flags: visibilityFlags | 1
                    )
                }
            default:
                continue
            }
        }
    }

    private func emitClassTypeParameterMetadataRegistration(
        for classSymbol: SymbolID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.intType
        let parameterSymbols = sema.types.nominalTypeParameterSymbols(for: classSymbol)
        let variances = sema.types.nominalTypeParameterVariances(for: classSymbol)
        for (index, parameterSymbol) in parameterSymbols.enumerated() {
            guard let parameter = sema.symbols.symbol(parameterSymbol) else { continue }
            let name = interner.resolve(parameter.name)
            let nameLiteral = interner.intern(name)
            let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
            let identity = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: parameterSymbol,
                sema: sema,
                interner: interner
            )
            let identityExpr = arena.appendExpr(.intLiteral(identity), type: intType)
            let nameExpr = arena.appendExpr(.stringLiteral(nameLiteral), type: intType)
            let varianceOrdinal: Int64
            if variances.indices.contains(index) {
                switch variances[index] {
                case .invariant: varianceOrdinal = 0
                case .in: varianceOrdinal = 1
                case .out: varianceOrdinal = 2
                }
            } else {
                varianceOrdinal = 0
            }
            let varianceExpr = arena.appendExpr(.intLiteral(varianceOrdinal), type: intType)
            let isReifiedOrdinal: Int64 = sema.symbols.symbol(parameterSymbol)?.flags.contains(.reifiedTypeParameter) == true
                ? 1 : 0
            let isReified = arena.appendExpr(.intLiteral(isReifiedOrdinal), type: intType)
            let declaredBounds = sema.symbols.typeParameterUpperBounds(for: parameterSymbol)
            let upperBounds = declaredBounds.isEmpty ? [sema.types.nullableAnyType] : declaredBounds
            let upperBoundTypes = upperBounds.map { bound in
                driver.lowerKTypeExpr(
                    for: bound,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions,
                    registerClassMetadata: false
                )
            }
            let upperBoundsExpr = makeReflectionArgumentList(
                upperBoundTypes,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            instructions.append(contentsOf: [
                .constValue(result: indexExpr, value: .intLiteral(Int64(index))),
                .constValue(result: identityExpr, value: .intLiteral(identity)),
                .constValue(result: nameExpr, value: .stringLiteral(nameLiteral)),
                .constValue(result: varianceExpr, value: .intLiteral(varianceOrdinal)),
                .constValue(result: isReified, value: .intLiteral(isReifiedOrdinal)),
            ])
            instructions.append(.call(
                callee: interner.intern("__kk_kclass_register_type_parameter"),
                arguments: [typeTokenExpr, indexExpr, identityExpr, nameExpr, varianceExpr, isReified, upperBoundsExpr],
                result: arena.appendTemporary(type: intType),
                canThrow: false
            ))
        }
    }

    func emitClassEnclosingMetadataRegistration(
        for classSymbol: SymbolID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.intType
        let classInfo = sema.symbols.symbol(classSymbol)
        let nominalKinds: Set<SymbolKind> = [.class, .interface, .object, .enumClass, .annotationClass]
        let directOwner = sema.symbols.parentSymbol(for: classSymbol)
        let isLocalOrAnonymous = classInfo?.fqName.contains { component in
            let name = interner.resolve(component)
            return name.hasPrefix("__localdecl_") || name.hasPrefix("__ObjectLiteral_")
        } == true

        func lexicallyContainingSymbols(matching predicate: (SemanticSymbol) -> Bool) -> [SemanticSymbol] {
            guard let classRange = classInfo?.declSite else { return [] }
            return sema.symbols.allSymbols().compactMap { candidate -> (SemanticSymbol, Int)? in
                guard candidate.id != classSymbol,
                      sema.symbols.parentSymbol(for: candidate.id) != classSymbol,
                      predicate(candidate),
                      let candidateRange = candidate.declSite,
                      candidateRange.contains(classRange)
                else {
                    return nil
                }
                return (candidate, candidateRange.end.offset - candidateRange.start.offset)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                // An initializer-local class belongs to the constructor when
                // its range ties the enclosing class's declaration range.
                if lhs.0.kind != rhs.0.kind {
                    if lhs.0.kind == .constructor { return true }
                    if rhs.0.kind == .constructor { return false }
                }
                return lhs.0.id.rawValue < rhs.0.id.rawValue
            }
            .map(\.0)
        }

        func namedEnclosingClass() -> SemanticSymbol? {
            var owner = directOwner
            while let candidate = owner, let info = sema.symbols.symbol(candidate) {
                if nominalKinds.contains(info.kind) { return info }
                owner = sema.symbols.parentSymbol(for: candidate)
            }
            guard let fqName = classInfo?.fqName, fqName.count > 1 else { return nil }
            for end in stride(from: fqName.count - 1, through: 1, by: -1) {
                let prefix = Array(fqName.prefix(end))
                if let candidate = sema.symbols.lookup(fqName: prefix),
                   let info = sema.symbols.symbol(candidate),
                   nominalKinds.contains(info.kind) {
                    return info
                }
            }
            return nil
        }

        var enclosingClassName = namedEnclosingClass()
            .map { $0.fqName.map(interner.resolve).joined(separator: ".") }
        if enclosingClassName == nil, isLocalOrAnonymous {
            enclosingClassName = lexicallyContainingSymbols(matching: { nominalKinds.contains($0.kind) })
                .first?.fqName.map(interner.resolve).joined(separator: ".")
        }
        if enclosingClassName == nil,
           let fileID = sema.symbols.sourceFileID(for: classSymbol) ?? classInfo?.declSite?.start.file {
            enclosingClassName = driver.ctx.lambdaEnclosingClassNamesByFileID[fileID]
        }

        let declaringClassName: String?
        if !isLocalOrAnonymous, let owner = namedEnclosingClass() {
            declaringClassName = owner.fqName.map(interner.resolve).joined(separator: ".")
        } else {
            declaringClassName = nil
        }

        var enclosingMember: SemanticSymbol?
        var currentOwner = directOwner
        while let owner = currentOwner, let ownerInfo = sema.symbols.symbol(owner) {
            if ownerInfo.kind == .function || ownerInfo.kind == .constructor {
                let parentKind = sema.symbols.parentSymbol(for: owner)
                    .flatMap { sema.symbols.symbol($0)?.kind }
                if parentKind.map({ nominalKinds.contains($0) || $0 == .package }) ?? true {
                    enclosingMember = ownerInfo
                    break
                }
            } else if ownerInfo.kind == .property {
                break
            }
            currentOwner = sema.symbols.parentSymbol(for: owner)
        }
        if enclosingMember == nil, isLocalOrAnonymous {
            enclosingMember = lexicallyContainingSymbols(matching: {
                $0.kind == .function || $0.kind == .constructor
            }).first
        }

        var memberKind: Int64 = 0
        var memberName = ""
        var memberSignature = ""
        if let enclosingMember {
            if enclosingMember.kind == .constructor {
                memberKind = 2
                memberName = "<init>"
                var parameterTypes = sema.symbols.functionSignature(for: enclosingMember.id)?.parameterTypes ?? []
                let constructorOwner = sema.symbols.parentSymbol(for: enclosingMember.id)
                    .flatMap(sema.symbols.symbol)
                if constructorOwner?.kind == .enumClass {
                    parameterTypes = [sema.types.stringType, sema.types.intType] + parameterTypes
                }
                let parameterTokens = parameterTypes.map { type in
                    String(RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
                        & ~RuntimeTypeCheckToken.nullableFlag)
                }
                let ownerType = sema.symbols.parentSymbol(for: enclosingMember.id)
                    .map { sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull))) }
                    ?? sema.types.anyType
                let returnToken = RuntimeTypeCheckToken.encode(type: ownerType, sema: sema, interner: interner)
                    & ~RuntimeTypeCheckToken.nullableFlag
                let returnName = sema.symbols.parentSymbol(for: enclosingMember.id)
                    .flatMap { sema.symbols.symbol($0)?.fqName.map(interner.resolve).joined(separator: ".") }
                    ?? enclosingClassName
                    ?? "java.lang.Object"
                memberSignature = "\(parameterTokens.joined(separator: ","))|\(returnToken)|\(returnName)"
            } else if let signature = sema.symbols.functionSignature(for: enclosingMember.id) {
                memberKind = 1
                memberName = interner.resolve(enclosingMember.name)
                var parameterTypes = signature.contextParameterTypes
                if let receiverType = signature.receiverType {
                    parameterTypes.append(receiverType)
                }
                parameterTypes.append(contentsOf: signature.parameterTypes)
                let parameterTokens = parameterTypes.map { type in
                    String(RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
                        & ~RuntimeTypeCheckToken.nullableFlag)
                }
                let returnToken = RuntimeTypeCheckToken.encode(
                    type: signature.returnType,
                    sema: sema,
                    interner: interner
                ) & ~RuntimeTypeCheckToken.nullableFlag
                memberSignature = "\(parameterTokens.joined(separator: ","))|\(returnToken)|\(javaReflectionTypeName(signature.returnType, sema: sema, interner: interner))"
            }
        }

        func stringExpression(_ value: String?) -> KIRExprID {
            guard let value else {
                let zero = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: zero, value: .intLiteral(0)))
                return zero
            }
            let literal = interner.intern(value)
            let expression = arena.appendExpr(.stringLiteral(literal), type: intType)
            instructions.append(.constValue(result: expression, value: .stringLiteral(literal)))
            return expression
        }

        let enclosingClassExpr = stringExpression(enclosingClassName)
        let declaringClassExpr = stringExpression(declaringClassName)
        let memberKindExpr = arena.appendExpr(.intLiteral(memberKind), type: intType)
        instructions.append(.constValue(result: memberKindExpr, value: .intLiteral(memberKind)))
        let memberNameExpr = stringExpression(memberKind == 0 ? nil : memberName)
        let memberSignatureExpr = stringExpression(memberKind == 0 ? nil : memberSignature)
        instructions.append(.call(
            callee: interner.intern("__kk_kclass_register_enclosing_metadata"),
            arguments: [
                typeTokenExpr,
                enclosingClassExpr,
                declaringClassExpr,
                memberKindExpr,
                memberNameExpr,
                memberSignatureExpr,
            ],
            result: arena.appendTemporary(type: intType),
            canThrow: false
        ))
    }

    private func javaReflectionTypeName(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> String {
        switch sema.types.kind(of: type) {
        case .unit, .platformUnit: return "void"
        case .nullableUnit: return "kotlin.Unit"
        case .nothing: return "java.lang.Void"
        case .stringStruct: return "java.lang.String"
        case let .primitive(primitive, _):
            switch primitive {
            case .boolean: return "boolean"
            case .char: return "char"
            case .int: return "int"
            case .long: return "long"
            case .float: return "float"
            case .double: return "double"
            case .byte: return "byte"
            case .short: return "short"
            case .uint: return "kotlin.UInt"
            case .ulong: return "kotlin.ULong"
            case .ubyte: return "kotlin.UByte"
            case .ushort: return "kotlin.UShort"
            }
        case let .classType(classType):
            return sema.symbols.symbol(classType.classSymbol)
                .map { $0.fqName.map(interner.resolve).joined(separator: ".") }
                ?? "java.lang.Object"
        case .error, .any, .intersection, .typeParam, .functionType, .kClassType:
            return "java.lang.Object"
        }
    }

    /// Registers enum entry fields and their runtime-retained annotations.
    /// Native reflection currently exposes this field subset only.
    private func emitJavaClassDeclaredFieldsRegistration(
        for classSymbol: SymbolID,
        typeTokenExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let owner = sema.symbols.symbol(classSymbol), owner.kind == .enumClass else { return }

        let intType = sema.types.intType
        let stringType = sema.types.stringType
        for fieldSymbol in sema.symbols.children(ofFQName: owner.fqName) {
            guard let field = sema.symbols.symbol(fieldSymbol),
                  sema.symbols.enumOwnerSymbol(for: field) == classSymbol
            else {
                continue
            }

            let fieldName = interner.resolve(field.name)
            let fieldNameInterned = interner.intern(fieldName)
            let fieldNameExpr = arena.appendExpr(.stringLiteral(fieldNameInterned), type: stringType)
            instructions.append(.constValue(result: fieldNameExpr, value: .stringLiteral(fieldNameInterned)))
            instructions.append(.call(
                callee: interner.intern("__kk_java_class_register_declared_field"),
                arguments: [typeTokenExpr, fieldNameExpr],
                result: arena.appendTemporary(type: intType),
                canThrow: false
            ))

            emitRuntimeAnnotationRegistration(
                annotations: sema.symbols.annotations(for: fieldSymbol),
                keyArguments: [typeTokenExpr, fieldNameExpr],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions,
                registrationCallee: "__kk_java_field_register_single_annotation",
                factoryRegistrationCallee: "__kk_java_field_register_annotation_factory"
            )
        }
    }

    /// Only nominal-token classifiers participate: builtin bases
    /// (`kotlin.Any`, `kotlin.String`, primitives, `FunctionN`) are answered
    /// by the runtime's builtin tables and never carry registry metadata.
    /// Other registration emitters (constructor allocation, object literals)
    /// call this with a set pre-seeded by the symbol they just registered so
    /// a sealed ancestor's subclass walk cannot re-emit it.
    func emitTransitiveSupertypeKClassMetadataRegistrations(
        for classSymbol: SymbolID,
        visitedClassSymbols: inout Set<SymbolID>,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        for superSymbolID in sema.symbols.directSupertypes(for: classSymbol)
        where !visitedClassSymbols.contains(superSymbolID) {
            let superType = sema.types.make(.classType(ClassType(
                classSymbol: superSymbolID, args: [], nullability: .nonNull
            )))
            let superToken = RuntimeTypeCheckToken.encode(type: superType, sema: sema, interner: interner)
            guard superToken & RuntimeTypeCheckToken.baseMask == RuntimeTypeCheckToken.nominalBase else {
                continue
            }
            let superTokenExpr = arena.appendExpr(.intLiteral(superToken), type: intType)
            instructions.append(.constValue(result: superTokenExpr, value: .intLiteral(superToken)))
            emitClassLiteralMetadataRegistrationImpl(
                classRefTargetType: superType,
                typeTokenExpr: superTokenExpr,
                visitedClassSymbols: &visitedClassSymbols,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
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
