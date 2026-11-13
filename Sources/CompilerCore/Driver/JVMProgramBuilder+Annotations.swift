import Foundation

extension JVMProgramBuilder {
    func aliases(_ declarations: [TypeAliasDecl], owner: SymbolID? = nil, package: [InternedString]? = nil) throws -> [JVMTypeAlias] {
        let prefix = owner.flatMap { sema.symbols.symbol($0)?.fqName } ?? package ?? ast.files.first(where: { context.sourceManager.origin(of: $0.fileID) == .user })!.packageFQName
        return try declarations.map { alias in
            guard let symbol = sema.symbols.lookup(fqName: prefix + [alias.name]), let underlying = sema.symbols.typeAliasUnderlyingType(for: symbol) else { throw JVMFrontendError(message: "Unsupported JVM typealias declaration.", range: alias.range) }
            return JVMTypeAlias(name: context.interner.resolve(alias.name), modifiers: alias.modifiers, typeParameters: try typeParameters(sema.symbols.typeAliasTypeParameters(for: symbol), declarations: alias.typeParams), underlyingType: try kotlinType(underlying), annotations: try metadataAnnotations(for: symbol, declaration: alias))
        }
    }

    func annotationConstant(_ id: ExprID, depth: Int = 0, includeDefaults: Bool = true) throws -> JVMAnnotationValue {
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
            switch try annotationConstant(operand, depth: depth + 1, includeDefaults: includeDefaults) {
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
                return .annotation(try annotationValue(parent, construction: id, includeDefaults: includeDefaults))
            }
            if case let .call(callee, _, _, _) = ast.arena.expr(id) {
                if let symbol = rawAnnotationSymbol(callee), annotationPlan(symbol) != nil { return .annotation(try annotationValue(symbol, construction: id, includeDefaults: includeDefaults)) }
                if case let .nameRef(name, _) = ast.arena.expr(callee), ["$annotationArrayLiteral", "arrayOf", "intArrayOf", "longArrayOf", "floatArrayOf", "doubleArrayOf", "booleanArrayOf", "charArrayOf", "byteArrayOf", "shortArrayOf"].contains(context.interner.resolve(name)) { return .array(try args.map { try annotationConstant($0.expr, depth: depth + 1, includeDefaults: includeDefaults) }) }
            }
            if let type = try? expressionType(id), type.referenceName?.hasPrefix("[") == true { return .array(try args.map { try annotationConstant($0.expr, depth: depth + 1, includeDefaults: includeDefaults) }) }
        default: break
        }
        if let symbol = sema.bindings.identifierSymbol(for: id) ?? rawAnnotationSymbol(id) {
            if let parent = sema.symbols.parentSymbol(for: symbol), sema.symbols.symbol(parent)?.kind == .enumClass { return .enumEntry("L" + (try className(parent)) + ";", context.interner.resolve(sema.symbols.symbol(symbol)!.name)) }
            if let declaration = declarationIDsBySymbol[symbol]?.first,
               case let .propertyDecl(property) = ast.arena.decl(declaration), property.modifiers.contains(.const), let initial = property.initializer { return try annotationConstant(initial, depth: depth + 1, includeDefaults: includeDefaults) }
        }
        throw JVMFrontendError(message: "Unsupported JVM annotation constant.", range: ast.arena.exprRange(id))
    }
    func annotationClassType(_ type: TypeID) throws -> String {
        let value = try classTokenType(type)
        return value.descriptor
    }
    func annotationPlan(_ symbol: SymbolID) -> JVMClassPlan? {
        if let plan = classes[symbol] { return plan.isAnnotation ? plan : nil }
        if let info = foreignAnnotationInfo(for: symbol) {
            let plan = JVMClassPlan(symbol: symbol, name: info.name)
            plan.foreignAnnotation = info
            return plan
        }
        guard let name = sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve).joined(separator: "."),
              [
                  "kotlin.Deprecated", "kotlin.ReplaceWith", "kotlin.SinceKotlin",
                  "kotlin.DeprecatedSinceKotlin", "kotlin.RequiresOptIn", "kotlin.ExperimentalUnsignedTypes",
              ].contains(name),
              let declaration = declarationIDsBySymbol[symbol]?.first,
              case let .classDecl(c) = ast.arena.decl(declaration), c.modifiers.contains(.annotationClass) else { return nil }
        return JVMClassPlan(symbol: symbol, name: name.replacingOccurrences(of: ".", with: "/"), declaration: c)
    }

    func foreignAnnotationInfo(for symbol: SymbolID) -> JVMClassInfo? {
        guard let name = try? className(symbol),
              let imports = context.jvmImports,
              let info = imports.classes[name],
              info.flags & 0x2000 != 0
        else { return nil }
        return info
    }

    func annotationValue(_ symbol: SymbolID, construction: ExprID?, includeDefaults: Bool = true) throws -> JVMAnnotation {
        guard let plan = annotationPlan(symbol) else { throw JVMFrontendError(message: "JVM annotation class is not available.") }
        if let foreign = plan.foreignAnnotation { return try foreignAnnotationValue(foreign, construction: construction, includeDefaults: includeDefaults) }
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
                guard let arguments = provided[i] else {
                    if includeDefaults, let initial = parameter.defaultValue {
                        values.append((context.interner.resolve(parameter.name), try annotationConstant(initial, includeDefaults: includeDefaults)))
                    } else if includeDefaults {
                        values.append((context.interner.resolve(parameter.name), .array([])))
                    }
                    continue
                }
                var items: [JVMAnnotationValue] = []
                for argument in arguments {
                    let constant = try annotationConstant(argument.expr, includeDefaults: includeDefaults)
                    if (argument.isSpread || argument.label != nil), case let .array(elements) = constant { items += elements }
                    else { items.append(constant) }
                }
                values.append((context.interner.resolve(parameter.name), .array(items)))
            } else if let expression = provided[i]?.first?.expr {
                values.append((context.interner.resolve(parameter.name), try annotationConstant(expression, includeDefaults: includeDefaults)))
            } else if let defaultValue = parameter.defaultValue {
                if includeDefaults { values.append((context.interner.resolve(parameter.name), try annotationConstant(defaultValue, includeDefaults: includeDefaults))) }
            } else {
                throw JVMFrontendError(message: "Missing JVM annotation argument.", range: plan.declaration?.range)
            }
        }
        let checked = try values.map { name, value -> (String, JVMAnnotationValue) in
            guard let declaration = plan.declaration!.memberProperties.first(where: { id in
                if case let .propertyDecl(p) = ast.arena.decl(id) { return context.interner.resolve(p.name) == name }; return false
            }), let symbol = sema.bindings.declSymbol(for: declaration), let semantic = sema.symbols.propertyType(for: symbol) else { throw JVMFrontendError(message: "Missing JVM annotation element.") }
            return (name, try checkedAnnotationValue(value, type: annotationElementType(type(semantic))))
        }
        return JVMAnnotation(descriptor: "L" + plan.name + ";", values: checked)
    }

    private func foreignAnnotationValue(_ info: JVMClassInfo, construction: ExprID?, includeDefaults: Bool) throws -> JVMAnnotation {
        let elements = context.jvmImports?.annotationElements(of: info) ?? []
        var provided: [Int: [JVMAnnotationValue]] = [:]
        if let construction {
            let args: [CallArgument]
            switch ast.arena.expr(construction) { case let .call(_, _, a, _), let .memberCall(_, _, _, a, _): args = a; default: args = [] }
            let binding = sema.bindings.callBinding(for: construction)
            for (i, arg) in args.enumerated() {
                let label = arg.label.map { context.interner.resolve($0) }
                let index = binding?.parameterMapping[i]
                    ?? arg.label.flatMap { label in elements.firstIndex { $0.name == context.interner.resolve(label) } }
                    ?? i
                guard elements.indices.contains(index), label == nil || label == elements[index].name,
                      elements[index].isVararg || provided[index] == nil
                else {
                    throw JVMFrontendError(message: "Invalid JVM annotation argument mapping.", range: ast.arena.exprRange(arg.expr))
                }
                let constant = try annotationConstant(arg.expr, includeDefaults: includeDefaults)
                if elements[index].isVararg, (arg.isSpread || arg.label != nil), case let .array(items) = constant {
                    provided[index, default: []] += items
                } else {
                    provided[index, default: []].append(constant)
                }
            }
        }
        var values: [(String, JVMAnnotationValue)] = []
        for (index, element) in elements.enumerated() {
            let arguments = provided[index] ?? []
            if element.isVararg {
                if arguments.isEmpty {
                    if includeDefaults {
                        if let defaultValue = element.defaultValue {
                            values.append((element.name, try checkedAnnotationValue(defaultValue, type: element.type)))
                        } else {
                            values.append((element.name, .array([])))
                        }
                    }
                } else {
                    values.append((element.name, try checkedAnnotationValue(.array(arguments), type: element.type)))
                }
                continue
            }
            guard let explicit = arguments.first else {
                if element.defaultValue == nil {
                    throw JVMFrontendError(message: "Missing JVM annotation argument.", range: construction.flatMap { ast.arena.exprRange($0) })
                }
                continue
            }
            values.append((element.name, try checkedAnnotationValue(explicit, type: element.type)))
        }
        return JVMAnnotation(descriptor: "L" + info.name + ";", values: values)
    }

    func annotationConstruction(_ record: MetadataAnnotationRecord) -> ExprID? {
        if let usage = record.usageID, let parsed = rawAnnotationConstructions[usage] { return parsed }
        if let factory = record.factorySymbol { return sema.bindings.annotationFactoryExpressions[factory] }
        guard let parts = record.usageID?.split(separator: ":"), parts.count == 2,
              let file = Int32(parts[0]), let offset = Int(parts[1]) else { return nil }
        return ast.arena.snapshot().expressions.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard let start = ast.arena.exprRange(id)?.start,
                  start.file.rawValue == file, start.offset == offset,
                  let binding = sema.bindings.callBinding(for: id),
                  sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor else { return nil }
            return id
        }.first
    }
    func annotations(for symbol: SymbolID, target: String?) throws -> [JVMAnnotation] {
        try groupedRepeatableAnnotations(annotationInstances(for: symbol, target: target, includeDefaults: true))
    }
    func metadataAnnotations(for symbol: SymbolID) throws -> [JVMAnnotation] {
        try annotationInstances(for: symbol, target: nil, includeDefaults: false)
    }
    func metadataAnnotations(for symbol: SymbolID, declaration: TypeAliasDecl) throws -> [JVMAnnotation] {
        for annotation in declaration.annotations {
            guard let usage = annotation.usageID,
                  rawAnnotationConstructions[usage] == nil,
                  var tokens = annotation.constructionTokens,
                  let last = tokens.last
            else { continue }
            if !tokens.contains(where: { $0.kind == .symbol(.lParen) }) {
                tokens += [Token(kind: .symbol(.lParen), range: last.range), Token(kind: .symbol(.rParen), range: last.range)]
            }
            let parser = BuildASTPhase.ExpressionParser(tokens: tokens, interner: context.interner, astArena: ast.arena, diagnostics: context.diagnostics)
            parser.allowAnnotationArrayLiterals = true
            guard let expression = parser.parse() else { throw JVMFrontendError(message: "Unsupported JVM typealias annotation arguments.", range: declaration.range) }
            rawAnnotationConstructions[usage] = expression
        }
        return try metadataAnnotations(for: symbol)
    }
    private func annotationInstances(for symbol: SymbolID, target: String?, includeDefaults: Bool) throws -> [JVMAnnotation] {
        var result: [JVMAnnotation] = []
        let records = try annotationRecords(for: symbol)
        // File annotations affect the source file/facade and are not emitted on
        // individual JVM declarations. They can coexist with member annotations.
        if let unsupported = records.first(where: { $0.useSiteTarget.map { !["field", "get", "set", "property", "param", "setparam", "receiver", "file", "delegate"].contains($0) } ?? false }) { throw JVMFrontendError(message: "Unsupported JVM annotation use-site target: " + unsupported.useSiteTarget!) }
        for record in records where record.useSiteTarget == target {
            let name = record.annotationFQName
            if [KnownCompilerAnnotation.repeatable.qualifiedName, KnownCompilerAnnotation.jvmRepeatable.qualifiedName].contains(name), classes[symbol]?.isAnnotation != true { throw JVMFrontendError(message: "JVM repeatable can only annotate annotation classes.") }
            if KnownCompilerAnnotation.jvmOverloads.matches(name) {
                guard sema.symbols.symbol(symbol)?.kind == .function else {
                    throw JVMFrontendError(message: "JVM @JvmOverloads currently supports functions only.")
                }
                continue
            }
            // WasExperimental stays dropped: it is internal in kotlin-stdlib, so
            // user code can never apply it legally, and no emitted JVM decl
            // carries it (its bundled-stdlib usages live on non-emitted files).
            if [
                KnownCompilerAnnotation.metadata.qualifiedName,
                KnownCompilerAnnotation.publishedApi.qualifiedName,
                KnownCompilerAnnotation.publishedApi.simpleName,
                KnownCompilerAnnotation.jvmInline.qualifiedName,
                KnownCompilerAnnotation.jvmName.qualifiedName,
                KnownCompilerAnnotation.jvmField.qualifiedName,
                KnownCompilerAnnotation.jvmSynthetic.qualifiedName,
                KnownCompilerAnnotation.suppress.qualifiedName,
                KnownCompilerAnnotation.suppress.simpleName,
                KnownCompilerAnnotation.optIn.qualifiedName,
                KnownCompilerAnnotation.retention.qualifiedName,
                KnownCompilerAnnotation.target.qualifiedName,
                KnownCompilerAnnotation.mustBeDocumented.qualifiedName,
                KnownCompilerAnnotation.repeatable.qualifiedName,
                KnownCompilerAnnotation.jvmRepeatable.qualifiedName,
                KnownCompilerAnnotation.wasExperimental.qualifiedName,
                KnownCompilerAnnotation.wasExperimental.simpleName,
            ].contains(name) { continue }
            let annotationOwner = sema.symbols.lookup(fqName: name.split(separator: ".").map { context.interner.intern(String($0)) })
            if isPlanlessKotlinInternalAnnotation(name, owner: annotationOwner) { continue }
            if JVMCompose.markers.contains(name), context.jvmImports?.hasComposeRuntime == true,
               let owner = annotationOwner, annotationPlan(owner)?.foreignAnnotation != nil,
               context.jvmImports?.classes[name.replacingOccurrences(of: ".", with: "/")]?.isAnnotation == true {
                result.append(JVMAnnotation(descriptor: "L" + name.replacingOccurrences(of: ".", with: "/") + ";", visible: false))
                continue
            }
            guard let owner = annotationOwner, annotationPlan(owner) != nil else { throw JVMFrontendError(message: "Unsupported JVM annotation: " + name) }
            let retention = annotationRetention(owner)
            if retention == "SOURCE" { continue }
            var annotation = try annotationValue(owner, construction: annotationConstruction(record), includeDefaults: includeDefaults)
            annotation.visible = retention != "BINARY"; result.append(annotation)
        }
        return result
    }
    /// kotlin.internal.* annotations are compile-time-only markers (inlining
    /// policy, overload resolution, inference constraints, parameter-name
    /// stability, runtime symbol naming). Consumer compiles inject them as
    /// residual-stdlib declarations that are never emitted, so no classfile
    /// plan exists to attach; stdlib builds still emit them where the
    /// annotation class itself is compiled.
    func isPlanlessKotlinInternalAnnotation(_ fqName: String, owner: SymbolID?) -> Bool {
        guard fqName.hasPrefix("kotlin.internal."), let owner else { return false }
        return annotationPlan(owner) == nil
    }
    func annotationRetention(_ symbol: SymbolID) -> String {
        guard let retention = sema.symbols.annotations(for: symbol).first(where: { $0.annotationFQName == KnownCompilerAnnotation.retention.qualifiedName })?.arguments.first else { return "RUNTIME" }
        return retention.components(separatedBy: CharacterSet.alphanumerics.inverted).last(where: { ["RUNTIME", "BINARY", "SOURCE"].contains($0) }) ?? "RUNTIME"
    }
    func annotationElementType(_ type: JVMValueType) throws -> JVMValueType {
        if type.referenceName == "kotlin/reflect/KClass" { return .reference("java/lang/Class", nullable: false) }
        if let name = type.referenceName, name == "[Lkotlin/reflect/KClass;" { return .reference("[Ljava/lang/Class;", nullable: false) }
        return type
    }
    func recordsContain(_ symbol: SymbolID, _ annotation: KnownCompilerAnnotation) -> Bool {
        sema.symbols.annotations(for: symbol).contains { $0.annotationFQName == annotation.qualifiedName }
    }
    func decorateAnnotation(_ plan: JVMClassPlan, result: inout JVMClass) throws {
        if let container = try repeatableContainerName(plan.symbol) {
            result.annotations.append(JVMAnnotation(descriptor: "Ljava/lang/annotation/Repeatable;", values: [("value", .classType("L" + container + ";"))]))
            if recordsContain(plan.symbol, .repeatable) { result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/annotation/Repeatable;")) }
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
        if recordsContain(plan.symbol, .retention) {
            result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/annotation/Retention;", values: [("value", .enumEntry("Lkotlin/annotation/AnnotationRetention;", retention))]))
        }
        result.annotations.append(JVMAnnotation(descriptor: "Ljava/lang/annotation/Retention;", values: [("value", .enumEntry("Ljava/lang/annotation/RetentionPolicy;", retention == "BINARY" ? "CLASS" : retention))]))
        let records = sema.symbols.annotations(for: plan.symbol)
        let targets = records.first { $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName }?.arguments ?? []
        if records.contains(where: { $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName }) {
            let mapping = ["CLASS": "TYPE", "ANNOTATION_CLASS": "ANNOTATION_TYPE", "TYPE_PARAMETER": "TYPE_PARAMETER", "FUNCTION": "METHOD", "PROPERTY_GETTER": "METHOD", "PROPERTY_SETTER": "METHOD", "FIELD": "FIELD", "VALUE_PARAMETER": "PARAMETER", "CONSTRUCTOR": "CONSTRUCTOR", "LOCAL_VARIABLE": "LOCAL_VARIABLE"]
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
        if records.contains(where: { $0.annotationFQName == KnownCompilerAnnotation.mustBeDocumented.qualifiedName }) { result.annotations.append(JVMAnnotation(descriptor: "Lkotlin/annotation/MustBeDocumented;")); result.annotations.append(JVMAnnotation(descriptor: "Ljava/lang/annotation/Documented;")) }
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

    func annotated(_ function: JVMFunction, symbol: SymbolID, signature providedSignature: FunctionSignature? = nil) throws -> JVMFunction {
        var f = function; f.annotations = try annotations(for: symbol, target: nil)
        applyDeprecation(f.annotations, to: &f)
        if let raw = sema.symbols.annotations(for: symbol).first(where: {
            $0.annotationFQName == KnownCompilerAnnotation.jvmName.qualifiedName && $0.useSiteTarget != "file"
        })?.arguments.first {
            let literal = raw.components(separatedBy: "=").last!.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = ("[" + literal + "]").data(using: .utf8), let names = try? JSONSerialization.jsonObject(with: data) as? [String], let name = names.first, (Self.isIdentifier(name) || context.options.stdlibOnly && Self.isIdentifier(name.replacingOccurrences(of: "-", with: "_"))) else { throw JVMFrontendError(message: "JVM @JvmName requires a constant ASCII identifier.") }
            f.jvmName = name
            f.annotations.append(JVMAnnotation(descriptor: "Lkotlin/jvm/JvmName;", values: [("name", .constant(.string(name)))], visible: false))
        }
        if let signature = providedSignature ?? sema.symbols.functionSignature(for: symbol) {
            for effect in sema.symbols.contractCallsInPlaceEffects(for: symbol) {
                if let index = signature.valueParameterSymbols.firstIndex(of: effect.parameterSymbol) {
                    f.callsInPlaceEffects[index] = effect.kind
                }
            }
            let leading = max(0, f.reference.parameters.count - signature.valueParameterSymbols.count)
            var leadingAnnotations = Array(repeating: [JVMAnnotation](), count: leading)
            if signature.receiverType != nil, !leadingAnnotations.isEmpty {
                leadingAnnotations[0] = try annotations(for: symbol, target: "receiver")
            }
            let valueParameterCount = min(signature.valueParameterSymbols.count, f.reference.parameters.count - leading)
            f.parameterAnnotations = leadingAnnotations + (try signature.valueParameterSymbols.prefix(valueParameterCount).map { try annotations(for: $0, target: nil) + annotations(for: $0, target: "param") })
        }
        return f
    }
}
