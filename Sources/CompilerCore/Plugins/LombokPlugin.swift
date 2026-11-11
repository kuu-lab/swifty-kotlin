import Foundation

/// kotlinc `lombok` (`org.jetbrains.kotlin.lombok`) compiler plugin equivalent.
/// Processes `@lombok.*` annotations on classes and properties (as well as
/// `lombok.config` supplied via `-P plugin:org.jetbrains.kotlin.lombok:config=<path>`)
/// and synthesizes the corresponding accessors, withers, constructors, `toString`,
/// `equals`/`hashCode`, `@Builder` types/factories, and logger fields.
struct LombokPlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.lombok"

    private static let getterFQ = "lombok.Getter"
    private static let setterFQ = "lombok.Setter"
    private static let withFQ = "lombok.With"
    private static let dataFQ = "lombok.Data"
    private static let valueFQ = "lombok.Value"
    private static let noArgsCtorFQ = "lombok.NoArgsConstructor"
    private static let allArgsCtorFQ = "lombok.AllArgsConstructor"
    private static let requiredArgsCtorFQ = "lombok.RequiredArgsConstructor"
    private static let toStringFQ = "lombok.ToString"
    private static let toStringIncludeFQ = "lombok.ToString.Include"
    private static let toStringExcludeFQ = "lombok.ToString.Exclude"
    private static let equalsAndHashCodeFQ = "lombok.EqualsAndHashCode"
    private static let equalsAndHashCodeIncludeFQ = "lombok.EqualsAndHashCode.Include"
    private static let equalsAndHashCodeExcludeFQ = "lombok.EqualsAndHashCode.Exclude"
    private static let builderFQ = "lombok.Builder"
    private static let accessorsFQ = "lombok.experimental.Accessors"
    private static let accessorsAltFQ = "lombok.Accessors"
    private static let nonNullFQ = "lombok.NonNull"
    private static let logAnnotations: Set<String> = [
        "lombok.extern.java.Log",
        "lombok.extern.slf4j.Slf4j",
        "lombok.extern.log4j.Log4j",
        "lombok.extern.log4j.Log4j2",
        "lombok.extern.apachecommons.CommonsLog",
        "lombok.extern.flogger.Flogger",
        "lombok.extern.jbosslog.JBossLog",
        "lombok.extern.slf4j.XSlf4j",
    ]

    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext) {
        let configPaths = context.pluginConfig.optionValues(for: id, key: "config")
        Self.applyLombok(configPaths: configPaths, context: context)
    }

    /// Runs Lombok Sema transformations for all annotated user classes in the module.
    /// Idempotent per class via `context.sema.lombokClasses`.
    static func applyLombok(
        configPaths: [String],
        context: CompilerPluginSemaContext
    ) {
        let config = loadLombokConfig(paths: configPaths)
        let symbols = context.symbols

        for symbol in symbols.allSymbols() {
            guard symbol.kind == .class,
                  !symbol.flags.contains(.importedLibrary),
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic),
                  context.sema.lombokClasses[symbol.id] == nil
            else { continue }

            let classAnnotations = symbols.annotations(for: symbol.id)
            let properties = collectInstanceProperties(of: symbol.id, symbols: symbols)
            let hasClassLombok = classAnnotations.contains { isLombokAnnotation($0.annotationFQName) }
            let hasPropLombok = properties.contains { propID in
                symbols.annotations(for: propID).contains { isLombokAnnotation($0.annotationFQName) }
            }
            guard hasClassLombok || hasPropLombok else { continue }

            processClass(
                symbol,
                classAnnotations: classAnnotations,
                properties: properties,
                config: config,
                context: context
            )
        }
    }

    // MARK: - Class Processing

    private static func processClass(
        _ classSymbol: SemanticSymbol,
        classAnnotations: [MetadataAnnotationRecord],
        properties: [SymbolID],
        config: LombokConfigFile,
        context: CompilerPluginSemaContext
    ) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let classID = classSymbol.id
        var info = LombokClassInfo()

        let ownTypeParams = types.nominalTypeParameterSymbols(for: classID)
        let enclosingTypeParams = types.enclosingTypeParameterSymbols(for: classID)
        let typeParamSymbols = enclosingTypeParams + ownTypeParams
        let selfArgs: (own: [TypeArg], enclosing: [TypeArg]) = (
            own: ownTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) },
            enclosing: enclosingTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) }
        )
        let classType = types.make(.classType(ClassType(
            classSymbol: classID,
            args: selfArgs.own,
            enclosingTypeArgs: selfArgs.enclosing,
            nullability: .nonNull
        )))

        let hasData = findAnnotation(classAnnotations, fqName: dataFQ) != nil
        let hasValue = findAnnotation(classAnnotations, fqName: valueFQ) != nil
        let dataStaticCtor = findAnnotation(classAnnotations, fqName: dataFQ)
            .flatMap { stringArgument($0, name: "staticConstructor") }
        let valueStaticCtor = findAnnotation(classAnnotations, fqName: valueFQ)
            .flatMap { stringArgument($0, name: "staticConstructor") }

        let classAccessors = parseAccessors(
            from: classAnnotations,
            defaults: AccessorSettings(
                fluent: config.accessorsFluent,
                chain: config.accessorsChain,
                prefixes: config.accessorsPrefix
            )
        )

        // 1. @Getter / @Setter / @With
        let classGetterAnn = findAnnotation(classAnnotations, fqName: getterFQ)
        let classSetterAnn = findAnnotation(classAnnotations, fqName: setterFQ)
        let classWithAnn = findAnnotation(classAnnotations, fqName: withFQ)

        for propID in properties {
            guard let propSym = symbols.symbol(propID) else { continue }
            let propAnns = symbols.annotations(for: propID)
            let propType = symbols.propertyType(for: propID) ?? types.anyType
            let propAccessors = parseAccessors(from: propAnns, defaults: classAccessors)
            let propAccessName = stripPrefixes(
                interner.resolve(propSym.name),
                prefixes: propAccessors.prefixes
            )

            // Getter
            let propGetterAnn = findAnnotation(propAnns, fqName: getterFQ)
            let effectiveGetterLevel: LombokAccessLevel? = {
                if let propGetterAnn {
                    return accessLevel(from: propGetterAnn)
                }
                if let classGetterAnn {
                    return accessLevel(from: classGetterAnn)
                }
                if hasData || hasValue {
                    return .public
                }
                return nil
            }()
            if let vis = effectiveGetterLevel?.visibility {
                let getterName = makeGetterName(
                    baseName: propAccessName,
                    isBoolean: isBooleanType(propType, types: types),
                    fluent: propAccessors.fluent,
                    noIsPrefix: config.getterNoIsPrefix
                )
                if let methodSym = defineMemberMethodIfAbsent(
                    ownerSymbol: classID,
                    ownerFQName: classSymbol.fqName,
                    name: getterName,
                    parameterTypes: [],
                    parameterNames: [],
                    returnType: propType,
                    receiverType: classType,
                    typeParamSymbols: typeParamSymbols,
                    visibility: vis,
                    context: context
                ) {
                    context.sema.lombokMethods[methodSym] = .getter(
                        ownerClass: classID,
                        propertySymbol: propID
                    )
                    info.methodSymbols.append(methodSym)
                }
            }

            // Setter (mutable properties only unless explicitly annotated on property)
            let propSetterAnn = findAnnotation(propAnns, fqName: setterFQ)
            let isMutable = propSym.flags.contains(.mutable)
            let effectiveSetterLevel: LombokAccessLevel? = {
                if let propSetterAnn {
                    return accessLevel(from: propSetterAnn)
                }
                if let classSetterAnn, isMutable {
                    return accessLevel(from: classSetterAnn)
                }
                if hasData, isMutable, !hasValue {
                    return .public
                }
                return nil
            }()
            if let vis = effectiveSetterLevel?.visibility {
                let setterName = makeSetterName(
                    baseName: propAccessName,
                    fluent: propAccessors.fluent
                )
                let returnsSelf = propAccessors.chain
                let returnType = returnsSelf ? classType : types.unitType
                if let methodSym = defineMemberMethodIfAbsent(
                    ownerSymbol: classID,
                    ownerFQName: classSymbol.fqName,
                    name: setterName,
                    parameterTypes: [propType],
                    parameterNames: [interner.resolve(propSym.name)],
                    returnType: returnType,
                    receiverType: classType,
                    typeParamSymbols: typeParamSymbols,
                    visibility: vis,
                    context: context
                ) {
                    context.sema.lombokMethods[methodSym] = .setter(
                        ownerClass: classID,
                        propertySymbol: propID,
                        returnsSelf: returnsSelf
                    )
                    info.methodSymbols.append(methodSym)
                }
            }

            // @With
            let propWithAnn = findAnnotation(propAnns, fqName: withFQ)
            let effectiveWithLevel: LombokAccessLevel? = {
                if let propWithAnn {
                    return accessLevel(from: propWithAnn)
                }
                if let classWithAnn {
                    return accessLevel(from: classWithAnn)
                }
                return nil
            }()
            if let vis = effectiveWithLevel?.visibility {
                let withName = "with" + capitalizeFirst(propAccessName)
                if let methodSym = defineMemberMethodIfAbsent(
                    ownerSymbol: classID,
                    ownerFQName: classSymbol.fqName,
                    name: withName,
                    parameterTypes: [propType],
                    parameterNames: [interner.resolve(propSym.name)],
                    returnType: classType,
                    receiverType: classType,
                    typeParamSymbols: typeParamSymbols,
                    visibility: vis,
                    context: context
                ) {
                    context.sema.lombokMethods[methodSym] = .with(
                        ownerClass: classID,
                        propertySymbol: propID
                    )
                    info.methodSymbols.append(methodSym)
                }
            }
        }

        // 2. @ToString
        if let toStringAnn = findAnnotation(classAnnotations, fqName: toStringFQ) ?? (hasData || hasValue ? MetadataAnnotationRecord(annotationFQName: toStringFQ) : nil) {
            let onlyIncluded = boolArgument(toStringAnn, name: "onlyExplicitlyIncluded") ?? config.toStringOnlyExplicitlyIncluded
            let includeFieldNames = boolArgument(toStringAnn, name: "includeFieldNames") ?? config.toStringIncludeFieldNames
            let excludedNames = stringListArgument(toStringAnn, name: "exclude")
            let explicitOfNames = stringListArgument(toStringAnn, name: "of")
            let includedProps = filterPropertiesForGeneratedMethod(
                properties,
                includeAnnotationFQ: toStringIncludeFQ,
                excludeAnnotationFQ: toStringExcludeFQ,
                onlyExplicitlyIncluded: onlyIncluded,
                excludedNames: excludedNames,
                ofNames: explicitOfNames,
                symbols: symbols,
                interner: interner
            )
            if let methodSym = defineMemberMethodIfAbsent(
                ownerSymbol: classID,
                ownerFQName: classSymbol.fqName,
                name: "toString",
                parameterTypes: [],
                parameterNames: [],
                returnType: types.stringType,
                receiverType: classType,
                typeParamSymbols: typeParamSymbols,
                visibility: .public,
                additionalFlags: [.overrideMember],
                context: context
            ) {
                context.sema.lombokMethods[methodSym] = .toStringMethod(
                    ownerClass: classID,
                    properties: includedProps,
                    includeFieldNames: includeFieldNames
                )
                info.methodSymbols.append(methodSym)
            }
        }

        // 3. @EqualsAndHashCode
        if let eqAnn = findAnnotation(classAnnotations, fqName: equalsAndHashCodeFQ) ?? (hasData || hasValue ? MetadataAnnotationRecord(annotationFQName: equalsAndHashCodeFQ) : nil) {
            let onlyIncluded = boolArgument(eqAnn, name: "onlyExplicitlyIncluded") ?? config.equalsOnlyExplicitlyIncluded
            let excludedNames = stringListArgument(eqAnn, name: "exclude")
            let explicitOfNames = stringListArgument(eqAnn, name: "of")
            let includedProps = filterPropertiesForGeneratedMethod(
                properties,
                includeAnnotationFQ: equalsAndHashCodeIncludeFQ,
                excludeAnnotationFQ: equalsAndHashCodeExcludeFQ,
                onlyExplicitlyIncluded: onlyIncluded,
                excludedNames: excludedNames,
                ofNames: explicitOfNames,
                symbols: symbols,
                interner: interner
            )
            if let eqSym = defineMemberMethodIfAbsent(
                ownerSymbol: classID,
                ownerFQName: classSymbol.fqName,
                name: "equals",
                parameterTypes: [types.nullableAnyType],
                parameterNames: ["other"],
                returnType: types.booleanType,
                receiverType: classType,
                typeParamSymbols: typeParamSymbols,
                visibility: .public,
                additionalFlags: [.overrideMember],
                context: context
            ) {
                context.sema.lombokMethods[eqSym] = .equalsMethod(
                    ownerClass: classID,
                    properties: includedProps
                )
                info.methodSymbols.append(eqSym)
            }
            if let hashSym = defineMemberMethodIfAbsent(
                ownerSymbol: classID,
                ownerFQName: classSymbol.fqName,
                name: "hashCode",
                parameterTypes: [],
                parameterNames: [],
                returnType: types.intType,
                receiverType: classType,
                typeParamSymbols: typeParamSymbols,
                visibility: .public,
                additionalFlags: [.overrideMember],
                context: context
            ) {
                context.sema.lombokMethods[hashSym] = .hashCodeMethod(
                    ownerClass: classID,
                    properties: includedProps
                )
                info.methodSymbols.append(hashSym)
            }
        }

        // 4. Constructors: @NoArgsConstructor, @RequiredArgsConstructor, @AllArgsConstructor
        if let noArgsAnn = findAnnotation(classAnnotations, fqName: noArgsCtorFQ) {
            let level = accessLevel(from: noArgsAnn)
            let force = boolArgument(noArgsAnn, name: "force") ?? false
            let staticName = stringArgument(noArgsAnn, name: "staticName")
            if let vis = level.visibility,
               let ctorSym = synthesizeConstructorIfAbsent(
                   classSymbol: classSymbol,
                   classType: classType,
                   typeParamSymbols: typeParamSymbols,
                   propertyParameters: [],
                   visibility: staticName != nil ? .private : vis,
                   runsInitializers: !force,
                   context: context
               )
            {
                info.constructorSymbols.append(ctorSym)
                if let staticName, !staticName.isEmpty {
                    let compID = ensureCompanionObject(for: classSymbol, info: &info, context: context)
                    if let factorySym = synthesizeStaticFactory(
                        name: staticName,
                        companionID: compID,
                        targetClassSymbol: classSymbol,
                        targetConstructor: ctorSym,
                        classType: classType,
                        propertyParameters: [],
                        typeParamSymbols: typeParamSymbols,
                        visibility: vis,
                        context: context
                    ) {
                        info.methodSymbols.append(factorySym)
                    }
                }
            }
        }

        if let reqAnn = findAnnotation(classAnnotations, fqName: requiredArgsCtorFQ) ?? (hasData && !hasValue ? MetadataAnnotationRecord(annotationFQName: requiredArgsCtorFQ) : nil) {
            let level = accessLevel(from: reqAnn)
            let staticName = stringArgument(reqAnn, name: "staticName") ?? dataStaticCtor
            let requiredProps = properties.filter { propID in
                guard let propSym = symbols.symbol(propID) else { return false }
                let isVal = !propSym.flags.contains(.mutable)
                let hasNonNull = findAnnotation(symbols.annotations(for: propID), fqName: nonNullFQ) != nil
                return isVal || hasNonNull
            }
            if let vis = level.visibility,
               let ctorSym = synthesizeConstructorIfAbsent(
                   classSymbol: classSymbol,
                   classType: classType,
                   typeParamSymbols: typeParamSymbols,
                   propertyParameters: requiredProps,
                   visibility: staticName != nil ? .private : vis,
                   runsInitializers: true,
                   context: context
               )
            {
                info.constructorSymbols.append(ctorSym)
                if let staticName, !staticName.isEmpty {
                    let compID = ensureCompanionObject(for: classSymbol, info: &info, context: context)
                    if let factorySym = synthesizeStaticFactory(
                        name: staticName,
                        companionID: compID,
                        targetClassSymbol: classSymbol,
                        targetConstructor: ctorSym,
                        classType: classType,
                        propertyParameters: requiredProps,
                        typeParamSymbols: typeParamSymbols,
                        visibility: vis,
                        context: context
                    ) {
                        info.methodSymbols.append(factorySym)
                    }
                }
            }
        }

        if let allAnn = findAnnotation(classAnnotations, fqName: allArgsCtorFQ) ?? (hasValue ? MetadataAnnotationRecord(annotationFQName: allArgsCtorFQ) : nil) {
            let level = accessLevel(from: allAnn)
            let staticName = stringArgument(allAnn, name: "staticName") ?? valueStaticCtor
            if let vis = level.visibility,
               let ctorSym = synthesizeConstructorIfAbsent(
                   classSymbol: classSymbol,
                   classType: classType,
                   typeParamSymbols: typeParamSymbols,
                   propertyParameters: properties,
                   visibility: staticName != nil ? .private : vis,
                   runsInitializers: true,
                   context: context
               )
            {
                info.constructorSymbols.append(ctorSym)
                if let staticName, !staticName.isEmpty {
                    let compID = ensureCompanionObject(for: classSymbol, info: &info, context: context)
                    if let factorySym = synthesizeStaticFactory(
                        name: staticName,
                        companionID: compID,
                        targetClassSymbol: classSymbol,
                        targetConstructor: ctorSym,
                        classType: classType,
                        propertyParameters: properties,
                        typeParamSymbols: typeParamSymbols,
                        visibility: vis,
                        context: context
                    ) {
                        info.methodSymbols.append(factorySym)
                    }
                }
            }
        }

        // 5. @Builder
        if let builderAnn = findAnnotation(classAnnotations, fqName: builderFQ) {
            synthesizeBuilder(
                for: classSymbol,
                classType: classType,
                typeParamSymbols: typeParamSymbols,
                properties: properties,
                builderAnn: builderAnn,
                config: config,
                info: &info,
                context: context
            )
        }

        // 6. Logging annotations (@Slf4j, @Log, etc.)
        if classAnnotations.contains(where: { logAnnotations.contains($0.annotationFQName) }) {
            let logName = interner.intern(config.logFieldName)
            let ownerForLog: SymbolID = config.logFieldIsStatic
                ? ensureCompanionObject(for: classSymbol, info: &info, context: context)
                : classID
            if let ownerSym = symbols.symbol(ownerForLog) {
                let logFQ = ownerSym.fqName + [logName]
                let exists = symbols.lookupAll(fqName: logFQ).contains {
                    symbols.symbol($0)?.kind == .property && symbols.parentSymbol(for: $0) == ownerForLog
                }
                if !exists {
                    let logProp = symbols.define(
                        kind: .property,
                        name: logName,
                        fqName: logFQ,
                        declSite: nil,
                        visibility: .private,
                        flags: [.synthetic, .static]
                    )
                    symbols.setParentSymbol(ownerForLog, for: logProp)
                    symbols.setPropertyType(types.anyType, for: logProp)
                    info.logPropertySymbol = logProp
                }
            }
        }

        context.sema.lombokClasses[classID] = info
    }

    // MARK: - Builder Synthesis

    private static func synthesizeBuilder(
        for classSymbol: SemanticSymbol,
        classType: TypeID,
        typeParamSymbols: [SymbolID],
        properties: [SymbolID],
        builderAnn: MetadataAnnotationRecord,
        config: LombokConfigFile,
        info: inout LombokClassInfo,
        context: CompilerPluginSemaContext
    ) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let classID = classSymbol.id
        let className = interner.resolve(classSymbol.name)

        let rawBuilderClassPattern = stringArgument(builderAnn, name: "builderClassName")
            ?? config.builderClassName
        let resolvedBuilderClassName = rawBuilderClassPattern.replacingOccurrences(of: "*", with: className)
        let builderClassName = resolvedBuilderClassName.isEmpty ? "\(className)Builder" : resolvedBuilderClassName
        let builderMethodName = stringArgument(builderAnn, name: "builderMethodName") ?? "builder"
        let buildMethodName = stringArgument(builderAnn, name: "buildMethodName") ?? "build"
        let setterPrefix = stringArgument(builderAnn, name: "setterPrefix") ?? ""

        let builderNameInterned = interner.intern(builderClassName)
        let builderFQ = classSymbol.fqName + [builderNameInterned]

        let builderClassID: SymbolID
        if let existing = symbols.lookup(fqName: builderFQ) {
            builderClassID = existing
        } else {
            let defined = symbols.define(
                kind: .class,
                name: builderNameInterned,
                fqName: builderFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classID, for: defined)
            builderClassID = defined
        }

        let ownTypeParams = types.nominalTypeParameterSymbols(for: builderClassID)
        let enclosingTypeParams = types.enclosingTypeParameterSymbols(for: builderClassID)
        let builderTypeParamSymbols = enclosingTypeParams + ownTypeParams
        let builderType = types.make(.classType(ClassType(
            classSymbol: builderClassID,
            args: ownTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) },
            enclosingTypeArgs: enclosingTypeParams.map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0)))) },
            nullability: .nonNull
        )))

        // Constructor for <Class>Builder
        let initName = interner.intern("<init>")
        let ctorFQ = builderFQ + [initName]
        let builderCtorID: SymbolID
        if let existingCtor = symbols.lookupAll(fqName: ctorFQ).first(where: {
            symbols.symbol($0)?.kind == .constructor
                && symbols.parentSymbol(for: $0) == builderClassID
                && symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        }) {
            builderCtorID = existingCtor
        } else {
            let ctorSym = symbols.define(
                kind: .constructor,
                name: builderNameInterned,
                fqName: ctorFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(builderClassID, for: ctorSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: builderType,
                    parameterTypes: [],
                    returnType: builderType,
                    valueParameterSymbols: [],
                    typeParameterSymbols: builderTypeParamSymbols,
                    classTypeParameterCount: builderTypeParamSymbols.count
                ),
                for: ctorSym
            )
            context.sema.pluginGeneratedConstructors[ctorSym] = PluginGeneratedConstructorInfo(
                runsInitializers: false
            )
            builderCtorID = ctorSym
        }

        // Builder fields & fluent setters
        var fieldPairs: [(builderProp: SymbolID, targetProp: SymbolID)] = []
        var setterMethods: [SymbolID] = []

        for targetPropID in properties {
            guard let targetPropSym = symbols.symbol(targetPropID) else { continue }
            let propNameStr = interner.resolve(targetPropSym.name)
            let propType = symbols.propertyType(for: targetPropID) ?? types.anyType

            let builderPropName = interner.intern(propNameStr)
            let builderPropFQ = builderFQ + [builderPropName]
            let builderPropID = symbols.define(
                kind: .property,
                name: builderPropName,
                fqName: builderPropFQ,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .mutable]
            )
            symbols.setParentSymbol(builderClassID, for: builderPropID)
            symbols.setPropertyType(propType, for: builderPropID)
            fieldPairs.append((builderProp: builderPropID, targetProp: targetPropID))

            let setterName = setterPrefix.isEmpty
                ? propNameStr
                : setterPrefix + capitalizeFirst(propNameStr)
            if let setterSym = defineMemberMethodIfAbsent(
                ownerSymbol: builderClassID,
                ownerFQName: builderFQ,
                name: setterName,
                parameterTypes: [propType],
                parameterNames: [propNameStr],
                returnType: builderType,
                receiverType: builderType,
                typeParamSymbols: builderTypeParamSymbols,
                visibility: .public,
                context: context
            ) {
                context.sema.lombokMethods[setterSym] = .builderSetter(
                    builderClass: builderClassID,
                    propertySymbol: builderPropID
                )
                setterMethods.append(setterSym)
            }
        }

        // build(): TargetClass
        let buildSym: SymbolID
        if let synthesized = defineMemberMethodIfAbsent(
            ownerSymbol: builderClassID,
            ownerFQName: builderFQ,
            name: buildMethodName,
            parameterTypes: [],
            parameterNames: [],
            returnType: classType,
            receiverType: builderType,
            typeParamSymbols: builderTypeParamSymbols,
            visibility: .public,
            context: context
        ) {
            context.sema.lombokMethods[synthesized] = .builderBuildMethod(
                targetClass: classID,
                builderClass: builderClassID,
                fieldPairs: fieldPairs
            )
            buildSym = synthesized
        } else {
            let buildNameInterned = interner.intern(buildMethodName)
            buildSym = symbols.lookupAll(fqName: builderFQ + [buildNameInterned]).first ?? .invalid
        }

        // Companion.builder(): BuilderType
        let compID = ensureCompanionObject(for: classSymbol, info: &info, context: context)
        if let compSym = symbols.symbol(compID) {
            let compType = types.make(.classType(ClassType(
                classSymbol: compID,
                args: [],
                enclosingTypeArgs: [],
                nullability: .nonNull
            )))
            if let factorySym = defineMemberMethodIfAbsent(
                ownerSymbol: compID,
                ownerFQName: compSym.fqName,
                name: builderMethodName,
                parameterTypes: [],
                parameterNames: [],
                returnType: builderType,
                receiverType: compType,
                typeParamSymbols: typeParamSymbols,
                visibility: .public,
                context: context
            ) {
                context.sema.lombokMethods[factorySym] = .builderFactoryMethod(
                    builderClass: builderClassID,
                    builderConstructor: builderCtorID
                )
                info.methodSymbols.append(factorySym)
            }
        }

        let builderInfo = LombokBuilderClassInfo(
            targetClassSymbol: classID,
            builderClassSymbol: builderClassID,
            constructorSymbol: builderCtorID,
            setterMethods: setterMethods,
            buildMethod: buildSym
        )
        info.builderInfo = builderInfo
        context.sema.lombokBuilderClasses[classID] = builderInfo
    }

    // MARK: - Constructors & Companion Factories

    private static func synthesizeConstructorIfAbsent(
        classSymbol: SemanticSymbol,
        classType: TypeID,
        typeParamSymbols: [SymbolID],
        propertyParameters: [SymbolID],
        visibility: Visibility,
        runsInitializers: Bool,
        context: CompilerPluginSemaContext
    ) -> SymbolID? {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let classID = classSymbol.id
        let initName = interner.intern("<init>")
        let ctorFQ = classSymbol.fqName + [initName]

        let existing = symbols.lookupAll(fqName: ctorFQ).filter {
            symbols.symbol($0)?.kind == .constructor && symbols.parentSymbol(for: $0) == classID
        }
        for ctor in existing {
            if let sig = symbols.functionSignature(for: ctor),
               sig.parameterTypes.count == propertyParameters.count
            {
                return nil
            }
        }

        let superCtor = resolveSuperNoArgConstructor(for: classID, context: context)

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: classSymbol.name,
            fqName: ctorFQ,
            declSite: nil,
            visibility: visibility,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(classID, for: ctorSymbol)

        var paramTypes: [TypeID] = []
        var valueParams: [SymbolID] = []
        for propID in propertyParameters {
            guard let propSym = symbols.symbol(propID) else { continue }
            let propType = symbols.propertyType(for: propID) ?? types.anyType
            let pSym = symbols.define(
                kind: .valueParameter,
                name: propSym.name,
                fqName: ctorFQ + [propSym.name],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: pSym)
            paramTypes.append(propType)
            valueParams.append(pSym)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: classType,
                parameterTypes: paramTypes,
                returnType: classType,
                valueParameterSymbols: valueParams,
                valueParameterHasDefaultValues: Array(repeating: false, count: paramTypes.count),
                valueParameterIsVararg: Array(repeating: false, count: paramTypes.count),
                typeParameterSymbols: typeParamSymbols,
                classTypeParameterCount: typeParamSymbols.count
            ),
            for: ctorSymbol
        )

        if let superCtor {
            context.bindings.bindConstructorDelegationCall(
                ctorSymbol,
                binding: CallBinding(
                    chosenCallee: superCtor,
                    substitutedTypeArguments: [],
                    parameterMapping: [:]
                )
            )
        }

        context.sema.pluginGeneratedConstructors[ctorSymbol] = PluginGeneratedConstructorInfo(
            runsInitializers: runsInitializers,
            propertyParameters: propertyParameters
        )
        return ctorSymbol
    }

    private static func resolveSuperNoArgConstructor(
        for classID: SymbolID,
        context: CompilerPluginSemaContext
    ) -> SymbolID? {
        let symbols = context.symbols
        let interner = context.interner
        let initName = interner.intern("<init>")
        guard let edgeSupertype = symbols.directSupertypes(for: classID).first(where: {
            let kind = symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }), let superclassInfo = symbols.symbol(edgeSupertype) else {
            return nil
        }
        return symbols.lookupAll(fqName: superclassInfo.fqName + [initName]).first {
            symbols.symbol($0)?.kind == .constructor
                && symbols.parentSymbol(for: $0) == edgeSupertype
                && (symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true)
        }
    }

    private static func synthesizeStaticFactory(
        name: String,
        companionID: SymbolID,
        targetClassSymbol: SemanticSymbol,
        targetConstructor: SymbolID,
        classType: TypeID,
        propertyParameters: [SymbolID],
        typeParamSymbols: [SymbolID],
        visibility: Visibility,
        context: CompilerPluginSemaContext
    ) -> SymbolID? {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        guard let compSym = symbols.symbol(companionID) else { return nil }
        let compType = types.make(.classType(ClassType(
            classSymbol: companionID,
            args: [],
            enclosingTypeArgs: [],
            nullability: .nonNull
        )))
        var paramTypes: [TypeID] = []
        var paramNames: [String] = []
        for propID in propertyParameters {
            guard let propSym = symbols.symbol(propID) else { continue }
            paramTypes.append(symbols.propertyType(for: propID) ?? types.anyType)
            paramNames.append(interner.resolve(propSym.name))
        }
        guard let methodSym = defineMemberMethodIfAbsent(
            ownerSymbol: companionID,
            ownerFQName: compSym.fqName,
            name: name,
            parameterTypes: paramTypes,
            parameterNames: paramNames,
            returnType: classType,
            receiverType: compType,
            typeParamSymbols: typeParamSymbols,
            visibility: visibility,
            context: context
        ) else {
            return nil
        }
        context.sema.lombokMethods[methodSym] = .staticConstructorFactory(
            targetClass: targetClassSymbol.id,
            constructorSymbol: targetConstructor
        )
        return methodSym
    }

    private static func ensureCompanionObject(
        for classSymbol: SemanticSymbol,
        info: inout LombokClassInfo,
        context: CompilerPluginSemaContext
    ) -> SymbolID {
        let symbols = context.symbols
        let interner = context.interner
        let classID = classSymbol.id
        if let existing = symbols.companionObjectSymbol(for: classID) {
            info.companionSymbol = existing
            return existing
        }
        let compName = interner.intern("Companion")
        let compID = symbols.define(
            kind: .object,
            name: compName,
            fqName: classSymbol.fqName + [compName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(classID, for: compID)
        symbols.setCompanionObjectSymbol(compID, for: classID)
        info.companionSymbol = compID
        return compID
    }

    // MARK: - Symbol Helpers

    private static func collectInstanceProperties(
        of classID: SymbolID,
        symbols: SymbolTable
    ) -> [SymbolID] {
        symbols.declaredChildren(of: classID).filter { childID in
            guard let sym = symbols.symbol(childID) else { return false }
            return sym.kind == .property
                && !sym.flags.contains(.synthetic)
                && !sym.flags.contains(.static)
        }
    }

    private static func defineMemberMethodIfAbsent(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        name: String,
        parameterTypes: [TypeID],
        parameterNames: [String],
        returnType: TypeID,
        receiverType: TypeID,
        typeParamSymbols: [SymbolID],
        visibility: Visibility,
        additionalFlags: SymbolFlags = [],
        context: CompilerPluginSemaContext
    ) -> SymbolID? {
        let symbols = context.symbols
        let interner = context.interner
        let methodName = interner.intern(name)
        let methodFQ = ownerFQName + [methodName]

        let existing = symbols.lookupAll(fqName: methodFQ).filter {
            symbols.symbol($0)?.kind == .function
                && symbols.parentSymbol(for: $0) == ownerSymbol
                && symbols.functionSignature(for: $0)?.parameterTypes.count == parameterTypes.count
        }
        if !existing.isEmpty {
            return nil
        }

        let methodSym = symbols.define(
            kind: .function,
            name: methodName,
            fqName: methodFQ,
            declSite: nil,
            visibility: visibility,
            flags: SymbolFlags.synthetic.union(additionalFlags)
        )
        symbols.setParentSymbol(ownerSymbol, for: methodSym)

        var valueParams: [SymbolID] = []
        for (idx, paramName) in parameterNames.enumerated() {
            let pInterned = interner.intern(paramName)
            let pSym = symbols.define(
                kind: .valueParameter,
                name: pInterned,
                fqName: methodFQ + [pInterned],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(methodSym, for: pSym)
            valueParams.append(pSym)
            _ = idx
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: valueParams,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterTypes.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count),
                typeParameterSymbols: typeParamSymbols,
                classTypeParameterCount: typeParamSymbols.count
            ),
            for: methodSym
        )
        return methodSym
    }

    // MARK: - Annotation & Config Parsing Helpers

    private enum LombokAccessLevel {
        case `public`
        case `protected`
        case package
        case `private`
        case none

        var visibility: Visibility? {
            switch self {
            case .public: return .public
            case .protected: return .protected
            case .package: return .internal
            case .private: return .private
            case .none: return nil
            }
        }
    }

    private struct AccessorSettings {
        var fluent: Bool
        var chain: Bool
        var prefixes: [String]
    }

    private struct LombokConfigFile {
        var accessorsFluent = false
        var accessorsChain = false
        var accessorsPrefix: [String] = []
        var getterNoIsPrefix = false
        var toStringIncludeFieldNames = true
        var toStringOnlyExplicitlyIncluded = false
        var equalsOnlyExplicitlyIncluded = false
        var builderClassName = "*Builder"
        var logFieldName = "log"
        var logFieldIsStatic = true
    }

    private static func loadLombokConfig(paths: [String]) -> LombokConfigFile {
        var config = LombokConfigFile()
        for rawPath in paths {
            guard !rawPath.isEmpty,
                  let content = try? String(contentsOfFile: rawPath, encoding: .utf8)
            else { continue }
            for rawLine in content.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                if let plusRange = line.range(of: "+=") {
                    let key = line[..<plusRange.lowerBound].trimmingCharacters(in: .whitespaces)
                    let value = line[plusRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if key == "lombok.accessors.prefix", !value.isEmpty {
                        config.accessorsPrefix.append(value)
                    }
                    continue
                }
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "lombok.accessors.fluent":
                    config.accessorsFluent = parseBool(value) ?? config.accessorsFluent
                case "lombok.accessors.chain":
                    config.accessorsChain = parseBool(value) ?? config.accessorsChain
                case "lombok.accessors.prefix":
                    config.accessorsPrefix = value.isEmpty ? [] : [value]
                case "lombok.getter.noIsPrefix":
                    config.getterNoIsPrefix = parseBool(value) ?? config.getterNoIsPrefix
                case "lombok.toString.includeFieldNames":
                    config.toStringIncludeFieldNames = parseBool(value) ?? config.toStringIncludeFieldNames
                case "lombok.toString.onlyExplicitlyIncluded":
                    config.toStringOnlyExplicitlyIncluded = parseBool(value) ?? config.toStringOnlyExplicitlyIncluded
                case "lombok.equalsAndHashCode.onlyExplicitlyIncluded":
                    config.equalsOnlyExplicitlyIncluded = parseBool(value) ?? config.equalsOnlyExplicitlyIncluded
                case "lombok.builder.className":
                    if !value.isEmpty { config.builderClassName = value }
                case "lombok.log.fieldName":
                    if !value.isEmpty { config.logFieldName = value }
                case "lombok.log.fieldIsStatic":
                    config.logFieldIsStatic = parseBool(value) ?? config.logFieldIsStatic
                default:
                    break
                }
            }
        }
        return config
    }

    private static func isLombokAnnotation(_ fqName: String) -> Bool {
        fqName.hasPrefix("lombok.")
    }

    private static func findAnnotation(
        _ annotations: [MetadataAnnotationRecord],
        fqName: String
    ) -> MetadataAnnotationRecord? {
        annotations.first { $0.annotationFQName == fqName }
    }

    private static func accessLevel(from annotation: MetadataAnnotationRecord) -> LombokAccessLevel {
        for arg in annotation.arguments {
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("access") || trimmed.hasPrefix("value") || !trimmed.contains("=") {
                if trimmed.contains("NONE") { return .none }
                if trimmed.contains("PRIVATE") { return .private }
                if trimmed.contains("PROTECTED") { return .protected }
                if trimmed.contains("PACKAGE") { return .package }
                if trimmed.contains("PUBLIC") { return .public }
            }
        }
        return .public
    }

    private static func parseAccessors(
        from annotations: [MetadataAnnotationRecord],
        defaults: AccessorSettings
    ) -> AccessorSettings {
        guard let ann = findAnnotation(annotations, fqName: accessorsFQ)
            ?? findAnnotation(annotations, fqName: accessorsAltFQ)
        else { return defaults }
        var result = defaults
        if let fluent = boolArgument(ann, name: "fluent") {
            result.fluent = fluent
            if fluent && boolArgument(ann, name: "chain") == nil {
                result.chain = true
            }
        }
        if let chain = boolArgument(ann, name: "chain") {
            result.chain = chain
        }
        let prefixes = stringListArgument(ann, name: "prefix")
        if !prefixes.isEmpty {
            result.prefixes = prefixes
        }
        return result
    }

    private static func boolArgument(_ annotation: MetadataAnnotationRecord, name: String) -> Bool? {
        for arg in annotation.arguments {
            guard let eq = arg.firstIndex(of: "=") else { continue }
            let key = arg[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == name else { continue }
            let val = arg[arg.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return parseBool(val)
        }
        return nil
    }

    private static func stringArgument(_ annotation: MetadataAnnotationRecord, name: String) -> String? {
        for arg in annotation.arguments {
            guard let eq = arg.firstIndex(of: "=") else { continue }
            let key = arg[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == name else { continue }
            let raw = arg[arg.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return unquoteString(raw)
        }
        return nil
    }

    private static func stringListArgument(_ annotation: MetadataAnnotationRecord, name: String) -> [String] {
        var values: [String] = []
        for arg in annotation.arguments {
            guard let eq = arg.firstIndex(of: "=") else { continue }
            let key = arg[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == name else { continue }
            let raw = arg[arg.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = raw
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .replacingOccurrences(of: "arrayOf(", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ")"))
            for part in stripped.split(separator: ",") {
                let s = unquoteString(String(part).trimmingCharacters(in: .whitespacesAndNewlines))
                if !s.isEmpty { values.append(s) }
            }
        }
        return values
    }

    private static func parseBool(_ str: String) -> Bool? {
        switch str.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func unquoteString(_ str: String) -> String {
        if str.count >= 2, str.hasPrefix("\""), str.hasSuffix("\"") {
            return String(str.dropFirst().dropLast())
        }
        return str
    }

    private static func filterPropertiesForGeneratedMethod(
        _ properties: [SymbolID],
        includeAnnotationFQ: String,
        excludeAnnotationFQ: String,
        onlyExplicitlyIncluded: Bool,
        excludedNames: [String],
        ofNames: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SymbolID] {
        let excludedSet = Set(excludedNames)
        let ofSet = Set(ofNames)
        return properties.filter { propID in
            guard let propSym = symbols.symbol(propID) else { return false }
            let name = interner.resolve(propSym.name)
            let anns = symbols.annotations(for: propID)
            if !ofSet.isEmpty {
                return ofSet.contains(name)
            }
            if excludedSet.contains(name) || findAnnotation(anns, fqName: excludeAnnotationFQ) != nil {
                return false
            }
            if onlyExplicitlyIncluded {
                return findAnnotation(anns, fqName: includeAnnotationFQ) != nil
            }
            return true
        }
    }

    private static func isBooleanType(_ typeID: TypeID, types: TypeSystem) -> Bool {
        if typeID == types.booleanType { return true }
        if case let .primitive(.boolean, _) = types.kind(of: typeID) { return true }
        return false
    }

    private static func stripPrefixes(_ name: String, prefixes: [String]) -> String {
        for prefix in prefixes where !prefix.isEmpty && name.hasPrefix(prefix) {
            let remainder = String(name.dropFirst(prefix.count))
            guard let first = remainder.first else { continue }
            if first.isUppercase || prefix.last == "_" || first == "_" {
                let cleaned = remainder.drop { $0 == "_" }
                if let firstCleaned = cleaned.first {
                    return firstCleaned.lowercased() + String(cleaned.dropFirst())
                }
            }
        }
        return name
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + String(s.dropFirst())
    }

    private static func makeGetterName(
        baseName: String,
        isBoolean: Bool,
        fluent: Bool,
        noIsPrefix: Bool
    ) -> String {
        if fluent { return baseName }
        if isBoolean && !noIsPrefix {
            if baseName.hasPrefix("is"), baseName.dropFirst(2).first?.isUppercase == true {
                return baseName
            }
            return "is" + capitalizeFirst(baseName)
        }
        return "get" + capitalizeFirst(baseName)
    }

    private static func makeSetterName(baseName: String, fluent: Bool) -> String {
        if fluent { return baseName }
        return "set" + capitalizeFirst(baseName)
    }
}
