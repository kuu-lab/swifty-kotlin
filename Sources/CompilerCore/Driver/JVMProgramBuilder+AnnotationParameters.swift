import Foundation

extension JVMProgramBuilder {
    /// Name given to a property accessor by `@get:JvmName` / `@set:JvmName`, if any.
    /// The argument is evaluated as a Kotlin string constant (plain or raw literal,
    /// or a `const val` reference), not parsed as JSON.
    func explicitAccessorJvmName(for symbol: SymbolID, target: String) throws -> String? {
        guard let record = try annotationRecords(for: symbol).first(where: {
            $0.annotationFQName == KnownCompilerAnnotation.jvmName.qualifiedName && $0.useSiteTarget == target
        }), var raw = record.arguments.first else { return nil }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let eq = raw.firstIndex(of: "="), raw[..<eq].trimmingCharacters(in: .whitespaces) == "name" {
            raw = raw[raw.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var explicit = extractKotlinStringLiteralContent(raw).map { $0.isRaw ? $0.content : decodeKotlinStringEscapes($0.content) }
        if explicit == nil {
            // Not a literal (e.g. a `const val`): evaluate the first annotation argument.
            if let declaration = sourceDeclarations[symbol],
               let node = declaration.annotations.first(where: { $0.usageID != nil && $0.usageID == record.usageID }),
               var tokens = node.constructionTokens, let last = tokens.last {
                try rememberRawAnnotationConstruction(node, tokens: &tokens, lastToken: last, message: "Unsupported JVM @JvmName annotation arguments.")
            }
            if let construction = annotationConstruction(record) {
                switch ast.arena.expr(construction) {
                case let .call(_, _, args, _), let .memberCall(_, _, _, args, _):
                    if let argument = args.first {
                        // A bare name resolves through the enclosing declarations first
                        // (an object's `const val` shadows a top-level one).
                        var value: JVMAnnotationValue?
                        if case let .nameRef(name, _) = ast.arena.expr(argument.expr) {
                            var owner = sema.symbols.parentSymbol(for: symbol)
                            while let current = owner, value == nil {
                                if let fqName = sema.symbols.symbol(current)?.fqName,
                                   let found = sema.symbols.lookup(fqName: fqName + [name]),
                                   let declaration = declarationIDsBySymbol[found]?.first,
                                   case let .propertyDecl(property) = ast.arena.decl(declaration),
                                   property.modifiers.contains(.const), let initial = property.initializer {
                                    value = try annotationConstant(initial)
                                }
                                owner = sema.symbols.parentSymbol(for: current)
                            }
                        }
                        let evaluated = try value ?? annotationConstant(argument.expr)
                        if case let .constant(.string(text)) = evaluated { explicit = text }
                    }
                default: break
                }
            }
        }
        guard let name = explicit, Self.isIdentifier(name) else { throw JVMFrontendError(message: "Invalid JVM method name.") }
        return name
    }
    func annotationRecords(for symbol: SymbolID) throws -> [MetadataAnnotationRecord] {
        var records = sema.symbols.annotations(for: symbol)
        var nodes: [(AnnotationNode, String?)] = []
        if sema.symbols.symbol(symbol)?.kind == .constructor,
           let owner = sema.symbols.parentSymbol(for: symbol),
           let constructor = classes[owner]?.constructors.first(where: { $0.0 == symbol }) {
            nodes += constructor.1.annotations.map { ($0, $0.useSiteTarget) }
        }
        if let pair = sema.bindings.primaryConstructorPropertyParameters[symbol] {
            for node in pair.0.annotations {
                if let target = node.useSiteTarget, target != "param" { nodes.append((node, target)) }
                else if node.useSiteTarget == nil, let owner = annotationOwner(node, symbol: symbol) {
                    let targets = annotationTargets(owner)
                    if !targets.contains("VALUE_PARAMETER"), !targets.contains("PROPERTY"), targets.contains("FIELD") { nodes.append((node, "field")) }
                }
            }
        }
        if let owner = sema.symbols.valueParameterOwner(for: symbol),
           let parameters = sourceParameters[owner],
           let signature = sema.symbols.functionSignature(for: owner),
           let index = signature.valueParameterSymbols.firstIndex(of: symbol),
           parameters.indices.contains(index) {
            let parameter = parameters[index]
            for node in parameter.annotations where node.useSiteTarget == nil || node.useSiteTarget == "param" {
                if parameter.isProperty, node.useSiteTarget == nil, let annotation = annotationOwner(node, symbol: symbol), !annotationTargets(annotation).contains("VALUE_PARAMETER") { continue }
                nodes.append((node, node.useSiteTarget))
            }
        }
        for (node, target) in nodes {
            if sema.symbols.symbol(symbol)?.kind == .constructor,
               KnownCompilerAnnotation.jvmOverloads.matches(node.name) {
                if !records.contains(where: { $0.usageID != nil && $0.usageID == node.usageID }) {
                    records.append(MetadataAnnotationRecord(
                        annotationFQName: KnownCompilerAnnotation.jvmOverloads.qualifiedName,
                        arguments: node.arguments,
                        useSiteTarget: target,
                        usageID: node.usageID
                    ))
                }
                continue
            }
            if node.name == "Suppress" || node.name == "kotlin.Suppress" {
                // A user-defined `demo.Suppress` must keep its arguments, so
                // only drop the annotation once it resolves to kotlin.Suppress;
                // an unresolvable Suppress preserves the previous skip.
                let isKotlinSuppress = annotationOwner(node, symbol: symbol)
                    .flatMap { sema.symbols.symbol($0) }
                    .map { $0.fqName.map(context.interner.resolve).joined(separator: ".") == "kotlin.Suppress" } ?? true
                if isKotlinSuppress { continue }
            }
            guard let owner = annotationOwner(node, symbol: symbol), let info = sema.symbols.symbol(owner) else { throw JVMFrontendError(message: "Unresolved JVM parameter annotation: " + node.name) }
            // kotlin.internal.* annotations are compile-time-only markers;
            // consumer compiles inject them as residual-stdlib declarations
            // that are never emitted, so there is no classfile plan to attach
            // (mirrors the skip in annotations(for:)).
            let annotationFqName = info.fqName.map(context.interner.resolve).joined(separator: ".")
            if annotationFqName == "kotlin.OptIn" { continue }
            if isPlanlessKotlinInternalAnnotation(annotationFqName, owner: owner) { continue }
            if ["kotlin.jvm.Volatile", "kotlin.jvm.Transient"].contains(annotationFqName), target == "field" {
                if !node.arguments.isEmpty {
                    throw JVMFrontendError(message: "Too many arguments for 'constructor(): \(node.name)'.", range: node.constructionTokens?.first?.range)
                }
                if !records.contains(where: { $0.usageID != nil && $0.usageID == node.usageID }) {
                    records.append(MetadataAnnotationRecord(annotationFQName: annotationFqName, arguments: node.arguments, useSiteTarget: target, usageID: node.usageID))
                }
                continue
            }
            guard annotationPlan(owner) != nil else { throw JVMFrontendError(message: "Unsupported JVM parameter annotation: " + node.name) }
            if var tokens = node.constructionTokens, let last = tokens.last {
                try rememberRawAnnotationConstruction(node, tokens: &tokens, lastToken: last, message: "Unsupported JVM parameter annotation arguments.")
            }
            if !records.contains(where: { $0.usageID != nil && $0.usageID == node.usageID }) {
                records.append(MetadataAnnotationRecord(annotationFQName: info.fqName.map(context.interner.resolve).joined(separator: "."), arguments: node.arguments, useSiteTarget: target, usageID: node.usageID))
            }
        }
        var accessorTargets: [String: String] = [:]
        var isProperty = false
        for declaration in declarationIDsBySymbol[symbol] ?? [] {
            guard case let .propertyDecl(property)? = ast.arena.decl(declaration) else { continue }
            isProperty = true
            for annotation in property.annotations + (property.getter?.annotations ?? []) + (property.setter?.annotations ?? []) {
                if var tokens = annotation.constructionTokens, let last = tokens.last {
                    try rememberRawAnnotationConstruction(annotation, tokens: &tokens, lastToken: last, message: "Unsupported JVM property annotation arguments.")
                }
            }
            for annotation in property.getter?.annotations ?? [] {
                if let usageID = annotation.usageID { accessorTargets[usageID] = "get" }
            }
            for annotation in property.setter?.annotations ?? [] {
                if let usageID = annotation.usageID { accessorTargets[usageID] = "set" }
            }
        }
        records = records.map { record in
            guard record.useSiteTarget == nil,
                  let usageID = record.usageID,
                  let target = accessorTargets[usageID] else { return record }
            return MetadataAnnotationRecord(
                annotationFQName: record.annotationFQName,
                arguments: record.arguments,
                useSiteTarget: target,
                retention: record.retention,
                usageID: record.usageID,
                factorySymbol: record.factorySymbol,
                factoryLinkName: record.factoryLinkName
            )
        }
        if isProperty {
            records = records.map { record in
                guard record.useSiteTarget == nil,
                      let owner = sema.symbols.lookup(fqName: record.annotationFQName.split(separator: ".").map { context.interner.intern(String($0)) }), annotationPlan(owner)?.isAnnotation == true,
                      !annotationTargets(owner).contains("PROPERTY"), annotationTargets(owner).contains("FIELD") else { return record }
                return MetadataAnnotationRecord(annotationFQName: record.annotationFQName, arguments: record.arguments, useSiteTarget: "field", retention: record.retention, usageID: record.usageID, factorySymbol: record.factorySymbol, factoryLinkName: record.factoryLinkName)
            }
        }
        return records
    }

    func rememberRawAnnotationConstruction(
        _ node: AnnotationNode,
        tokens: inout [Token],
        lastToken: Token,
        message: String
    ) throws {
        if AnnotationParsingSupport.constructionArgumentListStart(in: tokens, name: node.name) == nil {
            tokens += [Token(kind: .symbol(.lParen), range: lastToken.range), Token(kind: .symbol(.rParen), range: lastToken.range)]
        }
        let parser = BuildASTPhase.ExpressionParser(tokens: tokens, interner: context.interner, astArena: ast.arena, diagnostics: context.diagnostics)
        parser.allowAnnotationArrayLiterals = true
        guard let expression = parser.parse(), let usage = node.usageID else { throw JVMFrontendError(message: message) }
        rawAnnotationConstructions[usage] = expression
    }

    func annotationOwner(_ node: AnnotationNode, symbol: SymbolID) -> SymbolID? {
        // Resolve against the file the annotation was written in; using the
        // first user file's imports would misresolve a same-named annotation
        // declared there (e.g. a custom `Suppress` shadowing kotlin.Suppress).
        let nodeFileID = node.constructionTokens?.first?.range.start.file
        let declaredFileID = sema.symbols.symbol(symbol)?.declSite?.start.file
        guard let file = ast.files.first(where: { $0.fileID == nodeFileID && context.sourceManager.origin(of: $0.fileID) == .user })
                ?? declaredFileID.flatMap({ ast.file(for: $0) })
                ?? ast.files.first(where: { context.sourceManager.origin(of: $0.fileID) == .user }) else { return nil }
        return resolveAnnotationSymbol(named: node.name, in: file, symbols: sema.symbols, interner: context.interner, types: sema.types, enclosingFQName: Array((sema.symbols.symbol(symbol)?.fqName ?? []).dropLast()))
    }
    func annotationTargets(_ owner: SymbolID) -> Set<String> {
        guard let record = sema.symbols.annotations(for: owner).first(where: { $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName }) else { return ["VALUE_PARAMETER", "PROPERTY", "FIELD"] }
        return Set(record.arguments.flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted) })
    }
    func rawAnnotationSymbol(_ id: ExprID) -> SymbolID? {
        if let symbol = sema.bindings.identifierSymbol(for: id) { return symbol }
        func path(_ id: ExprID) -> [InternedString]? {
            switch ast.arena.expr(id) {
            case let .nameRef(name, _): return [name]
            case let .memberCall(receiver, name, _, args, _) where args.isEmpty:
                return path(receiver).map { $0 + [name] }
            default: return nil
            }
        }
        guard let parts = path(id), let site = ast.arena.exprRange(id),
              let file = ast.file(for: site.start.file) else { return nil }
        let explicit = file.imports.compactMap { item -> [InternedString]? in
            guard !item.isWildcard, (item.alias ?? item.path.last) == parts.first else { return nil }
            return item.path + parts.dropFirst()
        }
        var candidates = explicit + [file.packageFQName + parts, parts]
        candidates += file.imports.filter(\.isWildcard).map { $0.path + parts }
        candidates += TypeCheckScopeBuilder().makeDefaultImportPackages(interner: context.interner).map { $0 + parts }
        return candidates.lazy.compactMap { self.sema.symbols.lookup(fqName: $0) }.first
    }
}

extension JVMProgramBuilder {
    func checkedAnnotationValue(_ value: JVMAnnotationValue, type: JVMValueType) throws -> JVMAnnotationValue {
        switch (value, type) {
        case (.constant(.int), .int), (.constant(.long), .long), (.constant(.float), .float), (.constant(.double), .double), (.constant(.boolean), .boolean), (.constant(.string), .string), (.constant(.string), .reference("java/lang/String", _, _)): return value
        case let (.constant(.int(number)), .byte) where (-128...127).contains(number): return .integral(number, 66)
        case let (.constant(.int(number)), .short) where (-32768...32767).contains(number): return .integral(number, 83)
        case let (.constant(.int(number)), .char) where (0...65535).contains(number): return .integral(number, 67)
        case let (.integral(number, tag), _) where (type == .byte && tag == 66 || type == .short && tag == 83 || type == .char && tag == 67): return .integral(number, tag)
        case let (.constant(.int(number)), .long): return .constant(.long(Int64(number)))
        case (.classType, .reference("java/lang/Class", _, _)): return value
        case let (.enumEntry(descriptor, _), _) where descriptor == type.descriptor: return value
        case let (.annotation(annotation), _) where annotation.descriptor == type.descriptor: return value
        case let (.array(elements), .reference(name, _, _)) where name.hasPrefix("["):
            let descriptor = String(name.dropFirst())
            let primitive: [String: JVMValueType] = ["B": .byte, "S": .short, "C": .char, "I": .int, "J": .long, "F": .float, "D": .double, "Z": .boolean]
            let element: JVMValueType
            if let type = primitive[descriptor] { element = type }
            else if descriptor.hasPrefix("L"), descriptor.hasSuffix(";") { element = .reference(String(descriptor.dropFirst().dropLast()), nullable: false) }
            else { throw JVMFrontendError(message: "Unsupported JVM annotation array element.") }
            return .array(try elements.map { try checkedAnnotationValue($0, type: element) })
        default: throw JVMFrontendError(message: "JVM annotation argument does not match element type " + type.descriptor + ".")
        }
    }
}
