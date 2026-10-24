/// This shared helper keeps KClass annotation registration identical across
/// metadata, class-reference, and object-literal lowering paths.
func emitKClassAnnotationRegistration(
    objectSymbol: SymbolID,
    typeTokenExpr: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction],
    registrationCallee: String = "__kk_kclass_register_single_annotation",
    annotations selectedAnnotations: [MetadataAnnotationRecord]? = nil
) {
    let annotations = selectedAnnotations ?? sema.symbols.annotations(for: objectSymbol)
    emitRuntimeAnnotationRegistration(
        annotations: annotations,
        keyArguments: [typeTokenExpr],
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions,
        registrationCallee: registrationCallee,
        registerJavaInheritedAnnotations: true
    )
}

func emitRuntimeAnnotationRegistration(
    annotations: [MetadataAnnotationRecord],
    keyArguments: [KIRExprID],
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction],
    registrationCallee: String,
    factoryRegistrationCallee: String? = nil,
    registerJavaInheritedAnnotations: Bool = false
) {
    let annotations = annotations.filter {
        resolvedAnnotationRetention($0, symbols: sema.symbols, interner: interner) == .runtime
    }
    guard !annotations.isEmpty else { return }

    let intType = sema.types.intType
    let stringType = sema.types.stringType

    for annotation in annotations {
        let nameInterned = interner.intern(annotation.annotationFQName)
        let nameExpr = arena.appendExpr(.stringLiteral(nameInterned), type: stringType)
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(nameInterned)))

        let argsEncoded = annotation.arguments.joined(separator: "|")
        let argsInterned = interner.intern(argsEncoded)
        let argsExpr = arena.appendExpr(.stringLiteral(argsInterned), type: stringType)
        instructions.append(.constValue(result: argsExpr, value: .stringLiteral(argsInterned)))

        let argCount = Int64(annotation.arguments.count)
        let argCountExpr = arena.appendExpr(.intLiteral(argCount), type: intType)
        instructions.append(.constValue(result: argCountExpr, value: .intLiteral(argCount)))

        var callee = registrationCallee
        var registrationArguments = keyArguments + [nameExpr, argsExpr, argCountExpr]
        var factory = annotation.factorySymbol
        if factory == nil, let linkName = annotation.factoryLinkName {
            let name = interner.intern(linkName)
            let imported = sema.symbols.lookup(fqName: [name]) ?? sema.symbols.define(
                kind: .function, name: name, fqName: [name], declSite: nil,
                visibility: .private, flags: [.synthetic]
            )
            sema.symbols.setFunctionSignature(FunctionSignature(
                parameterTypes: [], returnType: sema.types.anyType, canThrow: true
            ), for: imported)
            sema.symbols.setExternalLinkName(linkName, for: imported)
            factory = imported
        }
        if let factory {
            let pointer = arena.appendExpr(.symbolRef(factory), type: sema.types.anyType)
            instructions.append(.constValue(result: pointer, value: .symbolRef(factory)))
            registrationArguments.append(pointer)
            callee = factoryRegistrationCallee ?? (registrationCallee == "__kk_kcallable_register_single_annotation"
                ? "__kk_kcallable_register_annotation_factory" : "__kk_kclass_register_annotation_factory")
        }
        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            callee: interner.intern(callee),
            arguments: registrationArguments,
            result: registerResult,
            canThrow: false
        ))

        if registerJavaInheritedAnnotations,
           annotationTypeIsJavaInherited(annotation, sema: sema, interner: interner)
        {
            let inheritedResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                callee: interner.intern("__kk_java_class_register_inherited_annotation"),
                arguments: [nameExpr],
                result: inheritedResult,
                canThrow: false
            ))
        }
    }
}

private func annotationTypeIsJavaInherited(
    _ annotation: MetadataAnnotationRecord,
    sema: SemaModule,
    interner: StringInterner
) -> Bool {
    let fqName = annotation.annotationFQName.split(separator: ".").map { interner.intern(String($0)) }
    guard let annotationSymbol = sema.symbols.lookup(fqName: fqName) else { return false }
    return sema.symbols.annotations(for: annotationSymbol).contains {
        $0.annotationFQName == "java.lang.annotation.Inherited"
    }
}
