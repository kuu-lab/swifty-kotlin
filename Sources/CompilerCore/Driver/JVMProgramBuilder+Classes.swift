import Foundation

final class JVMClassPlan {
    let symbol: SymbolID
    let name: String
    let declaration: ClassDecl?
    let interface: InterfaceDecl?
    var object: ObjectDecl?
    var companionOwner: SymbolID?
    var enumParent: SymbolID?
    var enumEntry: EnumEntryDecl?
    var outer: SymbolID?
    var isAnonymous = false
    var captures: [JVMAnonymousCapture] = []
    var escapesInline = false
    var isFacade = false
    var delegateFields: [(SymbolID, ExprID, JVMField)] = []
    var propertyTokens: [SymbolID: JVMField] = [:]
    var delegatedMethods: [(SymbolID, JVMForeignMethod, JVMForeignMethod, JVMField)] = []
    var delegatedProperties: [(JVMProperty, JVMProperty, JVMField)] = []
    var anonymousSuper: JVMForeignMethod?
    var isInner: Bool { declaration?.isInner == true }
    var isObject: Bool { object != nil && !isAnonymous }
    var isEnum: Bool { declaration?.modifiers.contains(.enumModifier) == true && enumParent == nil }
    var superclass = "java/lang/Object"
    var interfaces: [String] = []
    var properties: [(DeclID, PropertyDecl, JVMProperty)] = []
    var methods: [(FunDecl, JVMForeignMethod)] = []
    var methodSymbols: [String: SymbolID] = [:]
    var constructors: [(SymbolID, ConstructorDecl, Bool)] = []
    var isAnnotation: Bool { declaration?.modifiers.contains(.annotationClass) == true }
    var isValue: Bool { declaration?.modifiers.contains(.value) == true }
    var isInterface: Bool { interface != nil || isAnnotation }
    var modifiers: Modifiers { declaration?.modifiers ?? interface!.modifiers }
    init(symbol: SymbolID, name: String, declaration: ClassDecl? = nil, interface: InterfaceDecl? = nil) {
        self.symbol = symbol; self.name = name; self.declaration = declaration; self.interface = interface
    }
}

extension JVMProgramBuilder {
    func className(_ symbol: SymbolID) throws -> String {
        guard let declaration = sema.symbols.symbol(symbol) else { throw JVMFrontendError(message: "Missing JVM class symbol.") }
        return JVMClasspathIndex.binaryName(declaration.id, sema: sema, ctx: context)
    }
    func access(_ modifiers: Modifiers, final: Bool = false) -> UInt16 {
        let visibility: UInt16 = modifiers.contains(.private) ? 2 : (modifiers.contains(.protected) ? 4 : 1)
        return visibility | (final ? 16 : 0)
    }
    func memberFinal(_ modifiers: Modifiers) -> Bool {
        !modifiers.contains(.abstract) && (modifiers.contains(.final) || modifiers.intersection([.open, .override]).isEmpty)
    }
    func validateParameters(_ parameters: [ValueParamDecl]) throws {
        guard context.options.stdlibOnly || !parameters.contains(where: \.isVararg) || parameters.count == 1 else {
            throw JVMFrontendError(message: "JVM source varargs currently require a single parameter.")
        }
    }
    func functionReference(_ function: FunDecl, symbol: SymbolID, member: Bool) throws -> JVMFunctionReference {
        let allowed: Modifiers = member ? [.public, .private, .internal, .protected, .open, .final, .abstract, .override, .inline, .tailrec, .suspend, .operator, .infix] : [.public, .private, .internal, .inline, .tailrec, .suspend, .operator, .infix]
        guard function.contextReceivers.isEmpty,
              function.modifiers.subtracting(allowed).isEmpty,
              let signature = sema.symbols.functionSignature(for: symbol) else { throw JVMFrontendError(message: "Unsupported JVM M5 function declaration.", range: function.range) }
        let interfaceMember = sema.symbols.parentSymbol(for: symbol).flatMap { sema.symbols.symbol($0)?.kind } == .interface
        if function.isTailrec && member && (!memberFinal(function.modifiers) || interfaceMember && !function.modifiers.contains(.private)) {
            throw JVMFrontendError(message: "tailrec is prohibited on open JVM members.", range: function.range)
        }
        if function.isInline { inlineDeclarations[symbol] = function }
        try validateParameters(function.valueParams)
        sourceParameters[symbol] = function.valueParams
        sourceDeclarations[symbol] = function
        let name = context.interner.resolve(function.name)
        guard Self.isIdentifier(name) else { throw JVMFrontendError(message: "Unsupported JVM function name.", range: function.range) }
        try validateSignature(signature, instance: member, extensionReceiver: function.receiverType != nil)
        if function.receiverType != nil { extensionSymbols.insert(symbol) }
        var parameters = try ((function.receiverType == nil ? [] : [signature.receiverType].compactMap { $0 }) + signature.parameterTypes).map(type)
        let offset = function.receiverType == nil ? 0 : 1
        for (i, parameter) in function.valueParams.enumerated() where parameter.isVararg {
            let component = try varargComponentType(signature.parameterTypes[i])
            parameters[i + offset] = .reference("[" + component.descriptor, nullable: false)
        }
        let result = try type(signature.returnType)
        let unsigned = parameters.contains { $0.unsignedName != nil }
        var internalName = unsigned ? name + "$unsigned$" + JVMNameHash.suffix(parameters.map { ($0.unsignedName ?? "_") + ($0.isNullable ? "?" : "") }.joined()) : name
        if let annotation = sema.symbols.annotations(for: symbol).first(where: { $0.annotationFQName == "kotlin.jvm.JvmName" }), let raw = annotation.arguments.first {
            let literal = raw.components(separatedBy: "=").last!.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = ("[" + literal + "]").data(using: .utf8), let names = try? JSONSerialization.jsonObject(with: data) as? [String], let explicit = names.first, (Self.isIdentifier(explicit) || context.options.stdlibOnly && Self.isIdentifier(explicit.replacingOccurrences(of: "-", with: "_"))) else { throw JVMFrontendError(message: "Invalid JVM method name.") }
            internalName += "$jvmName$" + explicit
        }
        return JVMFunctionReference(name: internalName, parameters: parameters, result: result, isSuspend: function.isSuspend)
    }
    func validateSignature(_ signature: FunctionSignature, instance: Bool, extensionReceiver: Bool = false) throws {
        let parameterTypes = (extensionReceiver ? [signature.receiverType].compactMap { $0 } : []) + signature.parameterTypes
        let parameters = try parameterTypes.map(type)
        let unsupportedReturn: Bool
        if case let .nothing(nullability) = sema.types.kind(of: signature.returnType) {
            unsupportedReturn = nullability != .nonNull
        } else {
            unsupportedReturn = false
        }
        guard !parameters.contains(.unit), parameters.reduce(instance ? 1 : 0, { $0 + $1.width }) <= 255,
              !unsupportedReturn,
              !parameterTypes.contains(where: { if case .nothing = sema.types.kind(of: $0) { return true }; return false }) else {
            throw JVMFrontendError(message: "Unsupported JVM signature or method parameter slot limit exceeded.")
        }
    }
    func prepareClasses(_ declarations: [DeclID]) throws {
        try collectNominals(declarations)
        for expr in ast.arena.snapshot().expressions {
            if case let .objectLiteral(_, id?, _) = expr, let symbol = sema.bindings.declSymbol(for: id), classes[symbol] == nil {
                try collectNominals([id], anonymous: true)
            }
        }
        for plan in classes.values.sorted(by: { $0.name < $1.name }) {
            guard plan.name.split(whereSeparator: { $0 == "/" || $0 == "$" }).allSatisfy({ Self.isIdentifier(String($0)) }) else { throw JVMFrontendError(message: "JVM classes require ASCII names.") }
            if let parent = plan.enumParent { plan.superclass = classes[parent]!.name }
            for parent in plan.enumParent == nil ? sema.symbols.directSupertypes(for: plan.symbol) : [] {
                let sourceName = try className(parent)
                let name = JVMClasspathIndex.builtinName(sourceName) ?? sourceName
                if name == "kotlin/Any" { continue }
                if plan.isEnum && sourceName == "kotlin/Enum" { plan.superclass = "java/lang/Enum"; continue }
                if !context.options.stdlibOnly && ["kotlin/reflect/KProperty", "kotlin/reflect/KMutableProperty"].contains(sourceName) { throw JVMFrontendError(message: "JVM does not support source implementations of reflection interfaces.") }
                if sourceName == "kotlin/CharSequence" { throw JVMFrontendError(message: "JVM supports CharSequence inputs but not source implementations.") }
                if sourceName == "kotlin/Number" { throw JVMFrontendError(message: "JVM M5 does not support source subclasses of kotlin.Number.") }
                if !context.options.stdlibOnly && ["kotlin/coroutines/CoroutineContext", "kotlin/Result"].contains(sourceName) { throw JVMFrontendError(message: "JVM M7 does not support source implementations of CoroutineContext or Result.") }
                if sourceName.hasPrefix("kotlin/collections/"), sourceName != "kotlin/collections/AbstractSet", !context.options.stdlibOnly, !sema.symbols.delegatedInterfaces(forClass: plan.symbol).contains(where: { sema.types.isNominalSubtypeSymbol($0, of: parent) }) { throw JVMFrontendError(message: "JVM M5 collection interfaces are available through factories; source implementations are unsupported.") }
                guard classes[parent] != nil || context.jvmImports?.classes[name] != nil || JVMClasspathIndex.builtinName(sourceName) != nil else { throw JVMFrontendError(message: "Unsupported JVM supertype: \(name)") }
                if sema.symbols.symbol(parent)?.kind == .interface { plan.interfaces.append(name) }
                else {
                    guard !plan.isInterface, plan.superclass == "java/lang/Object", context.jvmImports?.classes[name].map({ $0.flags & 16 == 0 }) ?? true else { throw JVMFrontendError(message: "Invalid JVM superclass.") }
                    plan.superclass = name
                }
            }
            let functionIDs = plan.declaration?.memberFunctions ?? plan.interface!.memberFunctions
            for id in functionIDs {
                guard case let .funDecl(f) = ast.arena.decl(id), let symbol = sema.bindings.declSymbol(for: id) else { throw JVMFrontendError(message: "Missing JVM member function.") }
                guard !plan.isInterface || !f.modifiers.contains(.private) else { throw JVMFrontendError(message: "JVM M5 targets Java 8; private interface methods are unsupported.", range: f.range) }
                let ref = try functionReference(f, symbol: symbol, member: true)
                var method = JVMForeignMethod(owner: plan.name, name: ref.name, descriptor: ref.descriptor, parameters: ref.parameters, result: ref.result, isStatic: false, isInterface: plan.isInterface, isAbstract: f.modifiers.contains(.abstract) || (plan.isInterface && f.body == .unit))
                method.isSpecial = f.modifiers.contains(.private)
                method.isSuspend = f.isSuspend
                methods[symbol] = method; plan.methods.append((f, method))
                plan.methodSymbols[method.name + method.descriptor] = symbol
            }
            try prepareProperties(plan, ids: plan.declaration?.memberProperties ?? plan.interface!.memberProperties)
            try prepareNominalMembers(plan)
            if let c = plan.declaration, !plan.isAnnotation, !plan.isObject, !plan.isAnonymous, plan.enumParent == nil {
                let owner = sema.symbols.symbol(plan.symbol)!
                for symbol in sema.symbols.lookupAll(fqName: owner.fqName + [context.interner.intern("<init>")]) {
                    guard let signature = sema.symbols.functionSignature(for: symbol), let site = sema.symbols.symbol(symbol)?.declSite else { throw JVMFrontendError(message: "Missing JVM constructor signature.") }
                    let primary = site == c.range
                    let declaration: ConstructorDecl
                    if primary { declaration = ConstructorDecl(range: c.range, modifiers: c.primaryConstructorModifiers, annotations: c.primaryConstructorAnnotations, valueParams: c.primaryConstructorParams) }
                    else if let secondary = c.secondaryConstructors.first(where: { $0.range == site }) { declaration = secondary }
                    else { throw JVMFrontendError(message: "Missing JVM secondary constructor.") }
                    guard !declaration.valueParams.contains(where: \.isVararg) else { throw JVMFrontendError(message: "JVM vararg constructors are unsupported.", range: declaration.range) }
                    try validateParameters(declaration.valueParams)
                    sourceParameters[symbol] = declaration.valueParams
                    guard declaration.modifiers.subtracting([.public, .protected, .internal, .private]).isEmpty else { throw JVMFrontendError(message: "Unsupported JVM constructor modifiers.") }
                    try validateSignature(signature, instance: true)
                    let parameters = try hiddenConstructorTypes(plan) + signature.parameterTypes.map(type)
                    guard parameters.reduce(plan.isEnum ? 3 : 1, { $0 + $1.width }) <= 255 else { throw JVMFrontendError(message: "JVM constructor parameter slot limit exceeded.", range: declaration.range) }
                    methods[symbol] = JVMForeignMethod(owner: plan.name, name: "<init>", descriptor: "(" + parameters.map(\.descriptor).joined() + ")V", parameters: parameters, result: .reference(plan.name, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
                    plan.constructors.append((symbol, declaration, primary))
                }
            }
        }
    }
    func prepareProperties(_ plan: JVMClassPlan, ids propertyIDs: [DeclID]) throws {
        for id in propertyIDs {
            guard case let .propertyDecl(p) = ast.arena.decl(id), let symbol = sema.bindings.declSymbol(for: id), let propertyType = sema.symbols.propertyType(for: symbol),
                  p.typeParams.isEmpty, (p.receiverType == nil || plan.isFacade), p.contextReceivers.isEmpty,
                  p.explicitBackingField == nil,
                  p.modifiers.subtracting([.public, .private, .protected, .internal, .open, .final, .abstract, .override, .lateinit, .const]).isEmpty,
                  p.getter?.isInline != true, p.setter?.isInline != true,
                  p.getter?.annotations.isEmpty ?? true, p.setter?.annotations.isEmpty ?? true else { throw JVMFrontendError(message: "Unsupported JVM property declaration.") }
            guard !plan.isInterface || (!p.modifiers.contains(.private) && p.getter?.visibility != .private && p.setter?.visibility != .private) else { throw JVMFrontendError(message: "JVM M5 targets Java 8; private interface accessors are unsupported.", range: p.range) }
            let name = context.interner.resolve(p.name)
            let type = plan.isAnnotation ? try annotationElementType(self.type(propertyType)) : try self.type(propertyType)
            let extensionReceiverSemantic = sema.symbols.extensionPropertyReceiverType(for: symbol)
            let extensionReceiver = try extensionReceiverSemantic.map(self.type)
            let getterParameters = extensionReceiver.map { [$0] } ?? []
            let setterParameters = getterParameters + [type]
            guard Self.isIdentifier(name), type != .unit else { throw JVMFrontendError(message: "Unsupported JVM property name/type.") }
            let isAbstract = p.modifiers.contains(.abstract) || (plan.isInterface && (p.getter?.body ?? .unit) == .unit)
            let capital = String(name.prefix(1)).uppercased() + name.dropFirst()
            let booleanIs = name.hasPrefix("is") && name.count > 2 && name.dropFirst(2).first!.isUppercase
            let collectionGetter = collectionPropertyGetter(plan, name: name)
            let getterName = collectionGetter ?? (plan.isAnnotation ? name : (booleanIs ? name : "get" + capital))
            let setterName = booleanIs ? "set" + name.dropFirst(2) : "set" + capital
            var getter = JVMForeignMethod(owner: plan.name, name: getterName, descriptor: "(" + getterParameters.map(\.descriptor).joined() + ")" + type.descriptor, parameters: getterParameters, result: type, isStatic: plan.isFacade, isInterface: plan.isInterface, isAbstract: isAbstract)
            getter.isSpecial = !plan.isFacade && (p.getter?.visibility == .private || p.modifiers.contains(.private))
            var setter: JVMForeignMethod?
            if p.isVar {
                setter = JVMForeignMethod(owner: plan.name, name: setterName, descriptor: "(" + setterParameters.map(\.descriptor).joined() + ")V", parameters: setterParameters, result: .unit, isStatic: plan.isFacade, isInterface: plan.isInterface, isAbstract: p.modifiers.contains(.abstract) || (plan.isInterface && (p.setter?.body ?? .unit) == .unit))
                setter?.isSpecial = !plan.isFacade && (p.setter?.visibility == .private || p.modifiers.contains(.private))
            }
            if case .nothing = sema.types.kind(of: propertyType) { throw JVMFrontendError(message: "JVM M5 does not expose Nothing properties; specify a supported type.", range: p.range) }
            let validator = DeclarationPositionValidator(astArena: ast.arena, interner: context.interner, diagnostics: nil)
            let backing = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
            let usesField: (ExprID) -> Bool = { self.sema.bindings.identifierSymbol(for: $0) == backing }
            let hasField = extensionReceiver == nil && !plan.isInterface && !p.modifiers.contains(.abstract) &&
                (!validator.accessorHasBody(p.getter) || (p.isVar && !validator.accessorHasBody(p.setter)) ||
                 validator.accessorUsesBackingField(p.getter, isBackingFieldReference: usesField) ||
                 validator.accessorUsesBackingField(p.setter, isBackingFieldReference: usesField))
            var fieldModifiers = p.modifiers
            if p.modifiers.contains(.lateinit), let visibility = p.setter?.visibility {
                fieldModifiers.subtract([.public, .private, .protected, .internal])
                switch visibility {
                case .public: fieldModifiers.insert(.public)
                case .private: fieldModifiers.insert(.private)
                case .protected: fieldModifiers.insert(.protected)
                case .internal: fieldModifiers.insert(.internal)
                }
            }
            let exposedField = sema.symbols.annotations(for: symbol).contains { $0.annotationFQName == "kotlin.jvm.JvmField" }
            let field = hasField && p.delegateExpression == nil ? JVMField(owner: plan.name, name: name, type: type, access: (p.modifiers.contains(.lateinit) || exposedField ? self.access(fieldModifiers) : 2) | (plan.isFacade ? 8 : 0) | (p.isVar || plan.isObject ? 0 : 16)) : nil
            var property = JVMProperty(name: name, type: type, getter: getter, setter: setter, field: field, modifiers: p.modifiers)
            property.kotlinType = try kotlinType(propertyType)
            property.kotlinReceiver = try extensionReceiverSemantic.map(kotlinType)
            property.genericSignature = try signatureType(propertyType)
            property.receiverGenericSignature = try extensionReceiverSemantic.map { try signatureType($0) }
            property.customGetter = (p.getter?.body ?? .unit) != .unit || (p.getter?.visibility.map { $0 != Visibility(modifiers: p.modifiers) } ?? false)
            property.customSetter = (p.setter?.body ?? .unit) != .unit || (p.setter?.visibility.map { $0 != Visibility(modifiers: p.modifiers) } ?? false)
            if p.delegateExpression != nil {
                let storage = sema.symbols.delegateStorageSymbol(for: symbol) ?? SymbolID(rawValue: -(symbol.rawValue + 50000))
                guard let semantic = sema.symbols.delegateProvideDelegateSymbol(for: symbol).flatMap({ sema.symbols.functionSignature(for: $0)?.returnType }) ?? sema.symbols.propertyType(for: storage) ?? p.delegateExpression.flatMap({ sema.bindings.exprType(for: $0) }) else { throw JVMFrontendError(message: "Missing JVM delegate storage type.", range: p.range) }
                property.delegateField = JVMField(owner: plan.name, name: name + "$delegate", type: try self.type(semantic), access: 2 | (plan.isObject ? 0 : 16) | (plan.isFacade ? 8 : 0))
                property.delegateSymbol = symbol
                if needsDelegateToken(symbol) { plan.propertyTokens[symbol] = JVMField(owner: plan.name, name: "$property$" + name, type: .reference("kotlin/reflect/KProperty", nullable: false), access: 0x101A) }
            }
            if var field = property.field {
                if p.modifiers.contains(.const) {
                    guard let initial = p.initializer, case let .constant(constant) = try annotationConstant(initial) else { throw JVMFrontendError(message: "JVM const property requires a primitive or String constant.", range: p.range) }
                    field = JVMField(owner: plan.companionOwner.flatMap { classes[$0]?.name } ?? field.owner,
                                     name: field.name, type: field.type, access: access(p.modifiers) | 0x18)
                    field.constantValue = constant
                }
                field.annotations = try annotations(for: symbol, target: "field")
                field.isDeprecated = try (annotations(for: symbol, target: nil) + annotations(for: symbol, target: "property")).contains { $0.descriptor == "Lkotlin/Deprecated;" }
                property.field = field
            }
            if !(try annotations(for: symbol, target: nil) + annotations(for: symbol, target: "property")).isEmpty {
                property.annotationsMethod = JVMForeignMethod(owner: plan.name, name: getterName + "$annotations", descriptor: "()V", parameters: [], result: .unit, isStatic: true, isInterface: plan.isInterface, isAbstract: false)
            }
            properties[symbol] = property; plan.properties.append((id, p, property))
        }
    }
    func emitClasses() throws -> [JVMClass] {
        var results: [JVMClass] = [], emitted: Set<SymbolID> = []
        while let plan = classes.values.filter({ !emitted.contains($0.symbol) && (!$0.isAnonymous || $0.anonymousSuper != nil) }).sorted(by: { ($0.isAnonymous ? 1 : 0, $0.name) < ($1.isAnonymous ? 1 : 0, $1.name) }).first {
            emitted.insert(plan.symbol)
            var functions: [JVMFunction] = []
            for (declaration, method) in plan.methods {
                let builder = JVMFunctionBuilder(program: self, declaration: declaration, reference: JVMFunctionReference(name: method.name, parameters: method.parameters, result: method.result), owner: plan)
                guard let symbol = plan.methodSymbols[method.name + method.descriptor], let signature = sema.symbols.functionSignature(for: symbol) else { throw JVMFrontendError(message: "Missing JVM member signature.") }
                builder.functionSymbol = symbol
                builder.semanticSignature = signature
                functions.append(try annotated(describe(builder.build(), signature: signature, parameters: declaration.typeParams), symbol: symbol))
            }
            for (_, declaration, property) in plan.properties {
                functions += try emitAccessors(plan, declaration, property)
            }
            if plan.isObject { functions.append(try emitObjectConstructor(plan)) }
            if plan.isAnonymous { functions.append(try emitAnonymousConstructor(plan)) }
            if plan.enumParent != nil {
                functions.append(try emitEnumEntryConstructor(plan))
                if let defaults = try emitEnumEntryDefaultConstructor(plan) { functions.append(defaults) }
            }
            for (symbol, declaration, primary) in plan.constructors {
                let ctor = try annotated(emitConstructor(plan, symbol, declaration, primary: primary), symbol: symbol)
                functions.append(ctor)
                if declaration.valueParams.contains(where: \.hasDefaultValue) { functions += try defaultConstructorMethods(plan, symbol: symbol, declaration: declaration, original: ctor, primary: primary) }
            }
            for (decl, method) in plan.methods {
                if decl.valueParams.contains(where: \.hasDefaultValue), let symbol = plan.methodSymbols[method.name + method.descriptor] { functions.append(try defaultFunction(symbol: symbol, declaration: decl, plan: plan)) }
            }
            functions += try delegationMethods(plan)
            functions += try nominalMethods(plan, existing: functions)
            var defaultImpls: JVMClass?
            if plan.isInterface {
                let defaults = effectiveInterfaceMethods(plan).values.filter { !$0.isAbstract }.sorted { jvmMemberKey($0) < jvmMemberKey($1) }
                functions += interfaceDefaultAccessBridges(plan, methods: defaults)
                defaultImpls = defaultImplsClass(for: plan, methods: defaults)
            } else {
                functions += interfaceDefaultForwarders(plan, existing: functions)
            }
            // Return types participate in JVM descriptors. Covariant overrides
            // therefore need bridges for calls through a superclass/interface.
            functions += try bridges(plan, functions: functions)
            functions += try collectionDelegationMethods(plan, existing: functions)
            functions += try collectionPropertyAliases(plan, existing: functions)
            var signatures: Set<String> = []
            guard functions.allSatisfy({ signatures.insert($0.reference.name + $0.reference.descriptor).inserted }) else { throw JVMFrontendError(message: "Clashing JVM member/accessor signatures in \(plan.name).") }
            let visibility: UInt16 = plan.modifiers.contains(.private) && !plan.escapesInline ? 0 : 1
            let hasEnumSubclasses = plan.isEnum && classes.values.contains { $0.enumParent == plan.symbol }
            let abstract = plan.modifiers.contains(.abstract) || plan.modifiers.contains(.sealed) ||
                (plan.isEnum && (plan.methods.contains { $0.1.isAbstract } || plan.properties.contains { $0.2.getter.isAbstract || $0.2.setter?.isAbstract == true }))
            let modality: UInt16 = abstract ? 0x0400 : (plan.modifiers.contains(.open) || hasEnumSubclasses || plan.escapesInline ? 0 : 16)
            let access: UInt16 = plan.isInterface ? ((plan.isAnnotation ? 0x2600 : 0x0600) | visibility) : (0x0020 | visibility | modality)
            var result = JVMClass(name: plan.name, superclass: plan.superclass, interfaces: plan.isAnnotation ? ["java/lang/annotation/Annotation"] : plan.interfaces, access: access | (plan.isEnum || plan.enumParent != nil ? 0x4000 : 0), functions: functions, properties: plan.properties.map { $0.2 } + plan.delegatedProperties.map { $0.0 }, modifiers: plan.modifiers)
            try decorateNominal(plan, result: &result)
            result.isAnnotation = plan.isAnnotation; result.isValue = plan.isValue
            result.annotations = try annotations(for: plan.symbol, target: nil)
            result.typeAliases = try aliases(plan.declaration?.nestedTypeAliases ?? plan.interface?.nestedTypeAliases ?? [], owner: plan.symbol)
            if plan.isValue { result.underlyingProperty = plan.declaration?.primaryConstructorParams.first.map { context.interner.resolve($0.name) } }
            if plan.isAnnotation { try decorateAnnotation(plan, result: &result) }
            result.isFunInterface = plan.interface?.isFunInterface == true
            let parameterSymbols = sema.types.nominalTypeParameterSymbols(for: plan.symbol)
            let parameterDeclarations = plan.isAnonymous ? parameterSymbols.map { TypeParamDecl(name: sema.symbols.symbol($0)!.name) } : (plan.declaration?.typeParams ?? plan.interface!.typeParams)
            result.typeParameters = try typeParameters(parameterSymbols, declarations: parameterDeclarations)
            var parentSignatures: [String: String] = [:]
            for parent in sema.symbols.directSupertypes(for: plan.symbol) {
                let source = try className(parent)
                let args = sema.symbols.supertypeTypeArgs(for: plan.symbol, supertype: parent)
                let metadataName = source.hasPrefix("kotlin/jvm/functions/Function") ? source.replacingOccurrences(of: "kotlin/jvm/functions/", with: "kotlin/") : source
                result.kotlinSupertypes.append(.named(metadataName, try args.map(kotlinArgument), nullable: false))
                let id = sema.types.make(.classType(ClassType(classSymbol: parent, args: args)))
                if source == "kotlin/Any" { parentSignatures["java/lang/Object"] = "Ljava/lang/Object;" }
                else { parentSignatures[JVMClasspathIndex.builtinName(source) ?? source] = try signatureType(id) }
            }
            if plan.isEnum { parentSignatures["java/lang/Enum"] = "Ljava/lang/Enum<L" + plan.name + ";>;" }
            let parents = ([plan.superclass] + plan.interfaces).map { parentSignatures[$0] ?? "L" + $0 + ";" }
            result.genericSignature = (result.typeParameters.isEmpty ? "" : "<" + result.typeParameters.map(\.signature).joined() + ">") + parents.joined()
            results.append(result)
            if let defaultImpls { results.append(defaultImpls) }
        }
        return results
    }
}
