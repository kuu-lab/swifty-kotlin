import Foundation

extension JVMProgramBuilder {
    /// Parameter annotations are not materialized as runtime factories by the
    /// shared frontend. Preserve their source tokens and evaluate constants here.
    func annotationRecords(for symbol: SymbolID) throws -> [MetadataAnnotationRecord] {
        var records = sema.symbols.annotations(for: symbol)
        var nodes: [(AnnotationNode, String?)] = []
        if let constructor = classes.values.flatMap({ $0.constructors }).first(where: { $0.0 == symbol }) {
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
        let owners = sourceDeclarations.map { ($0.key, $0.value.valueParams) } + classes.values.flatMap { $0.constructors.map { ($0.0, $0.1.valueParams) } }
        for (owner, parameters) in owners {
            guard let signature = sema.symbols.functionSignature(for: owner), let index = signature.valueParameterSymbols.firstIndex(of: symbol), parameters.indices.contains(index) else { continue }
            let parameter = parameters[index]
            for node in parameter.annotations where node.useSiteTarget == nil || node.useSiteTarget == "param" {
                if parameter.isProperty, node.useSiteTarget == nil, let annotation = annotationOwner(node, symbol: symbol), !annotationTargets(annotation).contains("VALUE_PARAMETER") { continue }
                nodes.append((node, node.useSiteTarget))
            }
        }
        for (node, target) in nodes {
            guard let owner = annotationOwner(node, symbol: symbol), let info = sema.symbols.symbol(owner) else { throw JVMFrontendError(message: "Unresolved JVM parameter annotation: " + node.name) }
            guard annotationPlan(owner) != nil else { throw JVMFrontendError(message: "Unsupported JVM parameter annotation: " + node.name) }
            if var tokens = node.constructionTokens, let last = tokens.last {
                if !tokens.contains(where: { $0.kind == .symbol(.lParen) }) {
                    tokens += [Token(kind: .symbol(.lParen), range: last.range), Token(kind: .symbol(.rParen), range: last.range)]
                }
                let parser = BuildASTPhase.ExpressionParser(tokens: tokens, interner: context.interner, astArena: ast.arena, diagnostics: context.diagnostics)
                parser.allowAnnotationArrayLiterals = true
                guard let expression = parser.parse(), let usage = node.usageID else { throw JVMFrontendError(message: "Unsupported JVM parameter annotation arguments.") }
                rawAnnotationConstructions[usage] = expression
            }
            if !records.contains(where: { $0.usageID != nil && $0.usageID == node.usageID }) {
                records.append(MetadataAnnotationRecord(annotationFQName: info.fqName.map(context.interner.resolve).joined(separator: "."), arguments: node.arguments, useSiteTarget: target, usageID: node.usageID))
            }
        }
        let isProperty = sema.bindings.declSymbols.contains { id, bound in
            guard bound == symbol, case .propertyDecl = ast.arena.decl(id) else { return false }; return true
        }
        if isProperty {
            records = records.map { record in
                guard record.useSiteTarget == nil,
                      let owner = sema.symbols.lookup(fqName: record.annotationFQName.split(separator: ".").map { context.interner.intern(String($0)) }), classes[owner]?.isAnnotation == true,
                      !annotationTargets(owner).contains("PROPERTY"), annotationTargets(owner).contains("FIELD") else { return record }
                return MetadataAnnotationRecord(annotationFQName: record.annotationFQName, arguments: record.arguments, useSiteTarget: "field", retention: record.retention, usageID: record.usageID, factorySymbol: record.factorySymbol, factoryLinkName: record.factoryLinkName)
            }
        }
        return records
    }
    func annotationOwner(_ node: AnnotationNode, symbol: SymbolID) -> SymbolID? {
        guard let file = ast.files.first(where: { context.sourceManager.origin(of: $0.fileID) == .user }) else { return nil }
        return resolveAnnotationSymbol(named: node.name, in: file, symbols: sema.symbols, interner: context.interner, types: sema.types, enclosingFQName: Array((sema.symbols.symbol(symbol)?.fqName ?? []).dropLast()))
    }
    func annotationTargets(_ owner: SymbolID) -> Set<String> {
        guard let record = sema.symbols.annotations(for: owner).first(where: { $0.annotationFQName == "kotlin.annotation.Target" }) else { return ["VALUE_PARAMETER", "PROPERTY", "FIELD"] }
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
        guard let parts = path(id), let file = ast.files.first(where: { context.sourceManager.origin(of: $0.fileID) == .user }) else { return nil }
        var candidates = [file.packageFQName + parts, parts]
        for prefix in ["kotlin", "kotlin.annotation", "kotlin.reflect"] { candidates.append(prefix.split(separator: ".").map { context.interner.intern(String($0)) } + parts) }
        for item in file.imports {
            if item.isWildcard { candidates.append(item.path + parts) }
            else if (item.alias ?? item.path.last) == parts.first { candidates.append(item.path + parts.dropFirst()) }
        }
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
