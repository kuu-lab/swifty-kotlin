import Foundation

extension JVMProgramBuilder {
    func aliases(_ declarations: [TypeAliasDecl], owner: SymbolID? = nil, package: [InternedString]? = nil) throws -> [JVMTypeAlias] {
        let prefix = owner.flatMap { sema.symbols.symbol($0)?.fqName } ?? package ?? ast.files.first(where: { context.sourceManager.origin(of: $0.fileID) == .user })!.packageFQName
        return try declarations.map { alias in
            guard alias.annotations.isEmpty, let symbol = sema.symbols.lookup(fqName: prefix + [alias.name]), let underlying = sema.symbols.typeAliasUnderlyingType(for: symbol) else { throw JVMFrontendError(message: "Unsupported JVM typealias declaration.", range: alias.range) }
            return JVMTypeAlias(name: context.interner.resolve(alias.name), modifiers: alias.modifiers, typeParameters: try typeParameters(sema.symbols.typeAliasTypeParameters(for: symbol), declarations: alias.typeParams), underlyingType: try kotlinType(underlying))
        }
    }

    func annotationConstant(_ id: ExprID, depth: Int = 0) throws -> JVMAnnotationValue {
        guard depth < 64 else { throw JVMFrontendError(message: "Recursive JVM annotation constant.") }
        if let constant = ConstPropertyEvaluator(ast: ast, sema: sema, interner: context.interner).constantExpression(id) {
            switch constant {
            case let .intLiteral(v): return Int32(exactly: v).map { .constant(.int($0)) } ?? .constant(.long(v))
            case let .charLiteral(v): return .constant(.int(Int32(v)))
            case let .uintLiteral(v): return .constant(.int(Int32(truncatingIfNeeded: v)))
            case let .ulongLiteral(v): return .constant(.long(Int64(bitPattern: v)))
            case let .longLiteral(v): return .constant(.long(v))
            case let .floatLiteral(v): return .constant(.float(Float(v)))
            case let .doubleLiteral(v): return .constant(.double(v))
            case let .boolLiteral(v): return .constant(.boolean(v))
            case let .stringLiteral(v): return .constant(.string(context.interner.resolve(v)))
            default: break
            }
        }
        switch ast.arena.expr(id) {
        case let .intLiteral(v, _): return Int32(exactly: v).map { .constant(.int($0)) } ?? .constant(.long(v))
        case let .charLiteral(v, _): return .constant(.int(Int32(v)))
        case let .uintLiteral(v, _): return .constant(.int(Int32(truncatingIfNeeded: v)))
        case let .ulongLiteral(v, _): return .constant(.long(Int64(bitPattern: v)))
        case let .longLiteral(v, _): return .constant(.long(v))
        case let .floatLiteral(v, _): return .constant(.float(Float(v)))
        case let .doubleLiteral(v, _): return .constant(.double(v))
        case let .boolLiteral(v, _): return .constant(.boolean(v))
        case let .stringLiteral(v, _): return .constant(.string(context.interner.resolve(v)))
        case let .unaryExpr(.unaryMinus, operand, _):
            switch try annotationConstant(operand, depth: depth + 1) {
            case let .constant(.int(v)): return .constant(.int(0 &- v))
            case let .constant(.long(v)): return .constant(.long(0 &- v))
            case let .constant(.float(v)): return .constant(.float(-v))
            case let .constant(.double(v)): return .constant(.double(-v))
            default: break
            }
        case let .callableRef(receiver, _, _):
            if let type = sema.bindings.classRefTargetType(for: id) { return .classType(try annotationClassType(type)) }
            if let receiver, let symbol = rawAnnotationSymbol(receiver) {
                return .classType(try annotationClassType(sema.types.make(.classType(ClassType(classSymbol: symbol, args: [])))))
            }
        case let .call(_, _, args, _), let .memberCall(_, _, _, args, _):
            if let binding = sema.bindings.callBinding(for: id), let parent = sema.symbols.parentSymbol(for: binding.chosenCallee), annotationPlan(parent) != nil {
                return .annotation(try annotationValue(parent, construction: id))
            }
            if case let .call(callee, _, _, _) = ast.arena.expr(id) {
                if let symbol = rawAnnotationSymbol(callee), annotationPlan(symbol) != nil { return .annotation(try annotationValue(symbol, construction: id)) }
                if case let .nameRef(name, _) = ast.arena.expr(callee), ["$annotationArrayLiteral", "arrayOf", "intArrayOf", "longArrayOf", "floatArrayOf", "doubleArrayOf", "booleanArrayOf", "charArrayOf", "byteArrayOf", "shortArrayOf"].contains(context.interner.resolve(name)) { return .array(try args.map { try annotationConstant($0.expr, depth: depth + 1) }) }
            }
            if let type = try? expressionType(id), type.referenceName?.hasPrefix("[") == true { return .array(try args.map { try annotationConstant($0.expr, depth: depth + 1) }) }
        default: break
        }
        if let symbol = sema.bindings.identifierSymbol(for: id) ?? rawAnnotationSymbol(id) {
            if let parent = sema.symbols.parentSymbol(for: symbol), sema.symbols.symbol(parent)?.kind == .enumClass { return .enumEntry("L" + (try className(parent)) + ";", context.interner.resolve(sema.symbols.symbol(symbol)!.name)) }
            if let declaration = sema.bindings.declSymbols.first(where: { $0.value == symbol })?.key,
               case let .propertyDecl(property) = ast.arena.decl(declaration), property.modifiers.contains(.const), let initial = property.initializer { return try annotationConstant(initial, depth: depth + 1) }
        }
        throw JVMFrontendError(message: "Unsupported JVM annotation constant.", range: ast.arena.exprRange(id))
    }
    func annotationClassType(_ type: TypeID) throws -> String {
        let value = try classTokenType(type)
        return value.descriptor
    }
    func annotationPlan(_ symbol: SymbolID) -> JVMClassPlan? {
        if let plan = classes[symbol] { return plan.isAnnotation ? plan : nil }
        guard let name = sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve).joined(separator: "."),
              ["kotlin.Deprecated", "kotlin.ReplaceWith"].contains(name),
              let declaration = sema.bindings.declSymbols.first(where: { $0.value == symbol })?.key,
              case let .classDecl(c) = ast.arena.decl(declaration), c.modifiers.contains(.annotationClass) else { return nil }
        return JVMClassPlan(symbol: symbol, name: name.replacingOccurrences(of: ".", with: "/"), declaration: c)
    }

    func annotationValue(_ symbol: SymbolID, construction: ExprID?) throws -> JVMAnnotation {
        guard let plan = annotationPlan(symbol) else { throw JVMFrontendError(message: "JVM annotation class is not available.") }
        let params = plan.declaration!.primaryConstructorParams
        var provided: [Int: [CallArgument]] = [:]
        if let construction {
            let args: [CallArgument]
            switch ast.arena.expr(construction) { case let .call(_, _, a, _), let .memberCall(_, _, _, a, _): args = a; default: args = [] }
            let binding = sema.bindings.callBinding(for: construction)
            for (i, arg) in args.enumerated() {
                let index = binding?.parameterMapping[i] ?? arg.label.flatMap { label in params.firstIndex { $0.name == label } } ?? (params.last?.isVararg == true ? min(i, params.count - 1) : i)
                guard params.indices.contains(index), arg.label == nil || arg.label == params[index].name,
                      params[index].isVararg || provided[index] == nil else { throw JVMFrontendError(message: "Invalid JVM annotation argument mapping.", range: ast.arena.exprRange(arg.expr)) }
                provided[index, default: []].append(arg)
            }
        }
        var values: [(String, JVMAnnotationValue)] = []
        for (i, parameter) in params.enumerated() {
            if parameter.isVararg {
                if provided[i] == nil, let initial = parameter.defaultValue {
                    values.append((context.interner.resolve(parameter.name), try annotationConstant(initial))); continue
                }
                var items: [JVMAnnotationValue] = []
                for argument in provided[i] ?? [] {
                    let constant = try annotationConstant(argument.expr)
                    if (argument.isSpread || argument.label != nil), case let .array(elements) = constant { items += elements }
                    else { items.append(constant) }
                }
                values.append((context.interner.resolve(parameter.name), .array(items)))
            } else if let expression = provided[i]?.first?.expr ?? parameter.defaultValue { values.append((context.interner.resolve(parameter.name), try annotationConstant(expression))) }
            else { throw JVMFrontendError(message: "Missing JVM annotation argument.", range: plan.declaration?.range) }
        }
        let checked = try values.map { name, value -> (String, JVMAnnotationValue) in
            guard let declaration = plan.declaration!.memberProperties.first(where: { id in
                if case let .propertyDecl(p) = ast.arena.decl(id) { return context.interner.resolve(p.name) == name }; return false
            }), let symbol = sema.bindings.declSymbol(for: declaration), let semantic = sema.symbols.propertyType(for: symbol) else { throw JVMFrontendError(message: "Missing JVM annotation element.") }
            return (name, try checkedAnnotationValue(value, type: annotationElementType(type(semantic))))
        }
        return JVMAnnotation(descriptor: "L" + plan.name + ";", values: checked)
    }
    func annotationConstruction(_ record: MetadataAnnotationRecord, owner: SymbolID) -> ExprID? {
        if let usage = record.usageID, let parsed = rawAnnotationConstructions[usage] { return parsed }
        if let factory = record.factorySymbol { return sema.bindings.annotationFactoryExpressions[factory] }
        guard let usage = record.usageID, let offset = Int(usage.split(separator: ":").last ?? "") else { return nil }
        return ast.arena.snapshot().expressions.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard ast.arena.exprRange(id)?.start.offset == offset, let binding = sema.bindings.callBinding(for: id), sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor else { return nil }
            return id
        }.first
    }
    func annotations(for symbol: SymbolID, target: String?) throws -> [JVMAnnotation] {
        var result: [JVMAnnotation] = []
        let records = try annotationRecords(for: symbol)
        if let unsupported = records.first(where: { $0.useSiteTarget.map { !["field", "get", "set", "property", "param", "setparam"].contains($0) } ?? false }) { throw JVMFrontendError(message: "Unsupported JVM annotation use-site target: " + unsupported.useSiteTarget!) }
        for record in records where record.useSiteTarget == target {
            let name = record.annotationFQName
            if ["kotlin.annotation.Repeatable", "kotlin.jvm.JvmRepeatable"].contains(name), classes[symbol]?.isAnnotation != true { throw JVMFrontendError(message: "JVM repeatable can only annotate annotation classes.") }
            if ["kotlin.Metadata", "kotlin.PublishedApi", "PublishedApi", "kotlin.jvm.JvmInline", "kotlin.jvm.JvmName", "kotlin.jvm.JvmField", "kotlin.jvm.JvmSynthetic", "kotlin.Suppress", "Suppress", "kotlin.OptIn", "kotlin.annotation.Retention", "kotlin.annotation.Target", "kotlin.annotation.MustBeDocumented", "kotlin.annotation.Repeatable", "kotlin.jvm.JvmRepeatable", "kotlin.SinceKotlin", "SinceKotlin", "kotlin.DeprecatedSinceKotlin", "DeprecatedSinceKotlin", "kotlin.WasExperimental", "WasExperimental"].contains(name) { continue }
            guard let owner = sema.symbols.lookup(fqName: name.split(separator: ".").map { context.interner.intern(String($0)) }), annotationPlan(owner) != nil else { throw JVMFrontendError(message: "Unsupported JVM annotation: " + name) }
            let retention = annotationRetention(owner)
            if retention == "SOURCE" { continue }
            var annotation = try annotationValue(owner, construction: annotationConstruction(record, owner: symbol))
            annotation.visible = retention != "BINARY"; result.append(annotation)
        }
        return try groupedRepeatableAnnotations(result)
    }
    func annotationRetention(_ symbol: SymbolID) -> String {
        guard let retention = sema.symbols.annotations(for: symbol).first(where: { $0.annotationFQName == "kotlin.annotation.Retention" })?.arguments.first else { return "RUNTIME" }
        return retention.components(separatedBy: CharacterSet.alphanumerics.inverted).last(where: { ["RUNTIME", "BINARY", "SOURCE"].contains($0) }) ?? "RUNTIME"
    }
    func annotationElementType(_ type: JVMValueType) throws -> JVMValueType {
        if type.referenceName == "kotlin/reflect/KClass" { return .reference("java/lang/Class", nullable: false) }
        if let name = type.referenceName, name == "[Lkotlin/reflect/KClass;" { return .reference("[Ljava/lang/Class;", nullable: false) }
        return type
    }
    func recordsContain(_ symbol: SymbolID, _ name: String) -> Bool {
        sema.symbols.annotations(for: symbol).contains { $0.annotationFQName == name }
    }
    func decorateAnnotation(_ plan: JVMClassPlan, result: inout JVMClass) throws {
        if let container = try repeatableContainerName(plan.symbol) {
            result.annotations.append(JVMAnnotation(descriptor: "Ljava/lang/annotation/Repeatable;", values: [("value", .classType("L" + container + ";"))]))
            if recordsContain(plan.symbol, "kotlin.annotation.Repeatable") { result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/annotation/Repeatable;")) }
        }
        let params = plan.declaration!.primaryConstructorParams
        let owner = sema.symbols.symbol(plan.symbol)!
        if let symbol = sema.symbols.lookupAll(fqName: owner.fqName + [context.interner.intern("<init>")]).first, let signature = sema.symbols.functionSignature(for: symbol) {
            let types = try params.enumerated().map { i, parameter in parameter.isVararg ? plan.properties.first { $0.2.name == context.interner.resolve(parameter.name) }!.2.type : try annotationElementType(type(signature.parameterTypes[i])) }
            var ctor = rawFunction(plan.name, name: "<init>", parameters: types, result: .unit, access: 1, locals: [], instructions: [], constructor: true)
            ctor.isSynthetic = false
            ctor.parameterNames = params.map { context.interner.resolve($0.name) }
            ctor.kotlinParameters = try params.enumerated().map { i, parameter in parameter.isVararg ? plan.properties.first { $0.2.name == context.interner.resolve(parameter.name) }!.2.kotlinType! : try kotlinType(signature.parameterTypes[i]) }
            ctor.parameterDefaultFlags = params.map(\.hasDefaultValue)
            ctor.parameterVarargTypes = try params.enumerated().map { i, parameter in
                parameter.isVararg ? try kotlinType(signature.parameterTypes[i]) : nil
            }
            result.annotationConstructor = ctor
        }
        let retention = annotationRetention(plan.symbol)
        if recordsContain(plan.symbol, "kotlin.annotation.Retention") {
            result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/annotation/Retention;", values: [("value", .enumEntry("Lkotlin/annotation/AnnotationRetention;", retention))]))
        }
        result.annotations.append(JVMAnnotation(descriptor: "Ljava/lang/annotation/Retention;", values: [("value", .enumEntry("Ljava/lang/annotation/RetentionPolicy;", retention == "BINARY" ? "CLASS" : retention))]))
        let records = sema.symbols.annotations(for: plan.symbol)
        let targets = records.first { $0.annotationFQName == "kotlin.annotation.Target" }?.arguments ?? []
        if records.contains(where: { $0.annotationFQName == "kotlin.annotation.Target" }) {
            let mapping = ["CLASS": "TYPE", "ANNOTATION_CLASS": "ANNOTATION_TYPE", "FUNCTION": "METHOD", "PROPERTY_GETTER": "METHOD", "PROPERTY_SETTER": "METHOD", "FIELD": "FIELD", "VALUE_PARAMETER": "PARAMETER", "CONSTRUCTOR": "CONSTRUCTOR", "LOCAL_VARIABLE": "LOCAL_VARIABLE"]
            var names: [String] = [], kotlinNames: [String] = []
            for argument in targets {
                for word in argument.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted) {
                    if let mapped = mapping[word], !names.contains(mapped) { names.append(mapped) }
                    if ["CLASS", "ANNOTATION_CLASS", "TYPE_PARAMETER", "PROPERTY", "FIELD", "LOCAL_VARIABLE", "VALUE_PARAMETER", "CONSTRUCTOR", "FUNCTION", "PROPERTY_GETTER", "PROPERTY_SETTER", "TYPE", "EXPRESSION", "FILE", "TYPEALIAS"].contains(word), !kotlinNames.contains(word) { kotlinNames.append(word) }
                }
            }
            result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/annotation/Target;", values: [("allowedTargets", .array(kotlinNames.map { .enumEntry("Lkotlin/annotation/AnnotationTarget;", $0) }))]))
            result.annotations.append(JVMAnnotation(descriptor: "Ljava/lang/annotation/Target;", values: [("value", .array(names.map { .enumEntry("Ljava/lang/annotation/ElementType;", $0) }))]))
        }
        if records.contains(where: { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" }) { result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/annotation/MustBeDocumented;")); result.annotations.append(JVMAnnotation(descriptor: "Ljava/lang/annotation/Documented;")) }
        // Annotation elements use primitive/String/Class/enum/annotation/array JVM types.
        for i in result.functions.indices {
            let name = result.functions[i].reference.name
            if let parameter = plan.declaration!.primaryConstructorParams.first(where: { context.interner.resolve($0.name) == name }), let expression = parameter.defaultValue { result.functions[i].annotationDefault = try checkedAnnotationValue(annotationConstant(expression), type: result.functions[i].reference.result) }
        }
    }
    func applyDeprecation(_ annotations: [JVMAnnotation], to function: inout JVMFunction) {
        guard let annotation = annotations.first(where: { $0.descriptor == "Lkotlin/Deprecated;" }) else { return }
        function.isDeprecated = true
        function.isHiddenByDeprecation = annotation.values.contains { name, value in
            if name == "level", case .enumEntry("Lkotlin/DeprecationLevel;", "HIDDEN") = value { return true }
            return false
        }
    }

    func annotated(_ function: JVMFunction, symbol: SymbolID) throws -> JVMFunction {
        var f = function; f.annotations = try annotations(for: symbol, target: nil)
        applyDeprecation(f.annotations, to: &f)
        if let raw = sema.symbols.annotations(for: symbol).first(where: { $0.annotationFQName == "kotlin.jvm.JvmName" })?.arguments.first {
            let literal = raw.components(separatedBy: "=").last!.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = ("[" + literal + "]").data(using: .utf8), let names = try? JSONSerialization.jsonObject(with: data) as? [String], let name = names.first, (Self.isIdentifier(name) || context.options.stdlibOnly && Self.isIdentifier(name.replacingOccurrences(of: "-", with: "_"))) else { throw JVMFrontendError(message: "JVM @JvmName requires a constant ASCII identifier.") }
            f.jvmName = name
            f.annotations.append(JVMAnnotation(descriptor: "Lkotlin/jvm/JvmName;", values: [("name", .constant(.string(name)))], visible: false))
        }
        if let signature = sema.symbols.functionSignature(for: symbol) {
            for effect in sema.symbols.contractCallsInPlaceEffects(for: symbol) {
                if let index = signature.valueParameterSymbols.firstIndex(of: effect.parameterSymbol) {
                    f.callsInPlaceEffects[index] = effect.kind
                }
            }
            let leading = max(0, f.reference.parameters.count - signature.valueParameterSymbols.count)
            f.parameterAnnotations = Array(repeating: [], count: leading) + (try signature.valueParameterSymbols.map { try annotations(for: $0, target: nil) + annotations(for: $0, target: "param") })
        }
        return f
    }
}
