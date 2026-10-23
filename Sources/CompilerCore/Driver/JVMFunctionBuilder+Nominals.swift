extension JVMFunctionBuilder {
    func singleton(_ plan: JVMClassPlan) throws -> JVMValue {
        let field = program.singletonField(plan), value = try value(field.type)
        instructions.append(.getStatic(field, value)); return value
    }
    func nominalValue(_ id: ExprID) throws -> JVMValue? {
        if let scalar = try scalarConstant(id) { return scalar }
        guard let symbol = program.sema.bindings.identifierSymbol(for: id) else { return nil }
        if let entry = program.sema.symbols.symbol(symbol) {
            let path = entry.fqName.map(context.interner.resolve)
            let field: JVMField?
            if path == ["kotlin", "text", "Regex"] || path == ["kotlin", "text", "Regex", "Companion"] {
                field = JVMField(owner: "kotlin/text/Regex", name: "Companion", type: .reference("kotlin/text/Regex$Companion", nullable: false), access: 0x19)
            } else if path.count == 4 && Array(path.prefix(3)) == ["kotlin", "text", "RegexOption"] {
                field = JVMField(owner: "kotlin/text/RegexOption", name: path[3], type: .reference("kotlin/text/RegexOption", nullable: false), access: 0x4019)
            } else { field = nil }
            if let field { let result = try value(field.type); instructions.append(.getStatic(field, result)); return result }
        }
        if program.sema.symbols.symbol(symbol)?.fqName.map(context.interner.resolve) == ["kotlin", "properties", "Delegates"] {
            let field = JVMField(owner: "kotlin/properties/Delegates", name: "INSTANCE", type: .reference("kotlin/properties/Delegates", nullable: false), access: 0x19)
            let result = try value(field.type); instructions.append(.getStatic(field, result)); return result
        }
        if let entry = program.sema.symbols.symbol(symbol), entry.kind == .field, let parent = program.sema.symbols.parentSymbol(for: symbol), (try? program.className(parent)) == "kotlin/LazyThreadSafetyMode" {
            let field = JVMField(owner: "kotlin/LazyThreadSafetyMode", name: context.interner.resolve(entry.name), type: .reference("kotlin/LazyThreadSafetyMode", nullable: false), access: 0x4019)
            let result = try value(field.type); instructions.append(.getStatic(field, result)); return result
        }
        if let plan = program.classes[symbol], plan.isObject { return try singleton(plan) }
        if let companion = program.sema.symbols.companionObjectSymbol(for: symbol), let plan = program.classes[companion], plan.isObject { return try singleton(plan) }
        if let entry = program.sema.symbols.symbol(symbol), entry.kind == .field,
           let parent = program.sema.symbols.parentSymbol(for: symbol), let plan = program.classes[parent], plan.isEnum,
           plan.declaration!.enumEntries.contains(where: { $0.name == entry.name }) {
            let field = program.enumField(plan, name: context.interner.resolve(entry.name)), result = try value(field.type)
            instructions.append(.getStatic(field, result)); return result
        }
        if let entry = program.sema.symbols.symbol(symbol), entry.kind == .field,
           let parent = program.sema.symbols.parentSymbol(for: symbol),
           program.sema.symbols.symbol(parent)?.kind == .enumClass,
           let owner = try? program.className(parent),
           let imported = context.jvmImports?.classes[owner], imported.flags & 0x4000 != 0 {
            let field = JVMField(owner: owner, name: context.interner.resolve(entry.name), type: .reference(owner, nullable: false), access: 0x4019)
            let result = try value(field.type); instructions.append(.getStatic(field, result)); return result
        }
        return nil
    }

    func nominalCall(_ id: ExprID, receiver: ExprID?, name: String?, args: [CallArgument]) throws -> JVMIntrinsicResult? {
        if let annotation = try annotationConstruction(args, id: id) { return annotation }
        if let binding = program.sema.bindings.callBinding(for: id),
           let method = program.methods[binding.chosenCallee], method.name == "copy", program.sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.synthetic) == true,
           let plan = program.classes.values.first(where: { $0.name == method.owner && $0.modifiers.contains(.data) }) {
            let object = try receiver.map(requireValue) ?? instance(id)
            let props = try program.dataProperties(plan)
            var ordered: [Int: JVMValue] = [:]
            for (i, argument) in args.enumerated() {
                guard !argument.isSpread, let target = binding.parameterMapping[i], props.indices.contains(target) else { throw fail("Unsupported JVM copy arguments.", id) }
                ordered[target] = try requireValue(argument.expr)
            }
            var values: [JVMValue] = [], masks = Array(repeating: UInt32(0), count: (props.count + 31) / 32)
            for (i, property) in props.enumerated() {
                if let supplied = ordered[i] { values.append(try convert(supplied, to: property.type)) }
                else {
                    masks[i / 32] |= UInt32(1) << UInt32(i % 32)
                    let zero: JVMConstant
                    switch property.type {
                    case .long, .ulong: zero = .long(0)
                    case .float: zero = .float(0)
                    case .double: zero = .double(0)
                    case .string, .reference, .unsignedArray: zero = .null
                    case .boolean: zero = .boolean(false)
                    default: zero = .int(0)
                    }
                    values.append(try constant(zero, property.type))
                }
            }
            if masks.contains(where: { $0 != 0 }) {
                var arguments = [object] + values
                for mask in masks { arguments.append(try constant(.int(Int32(bitPattern: mask)), .int)) }
                arguments.append(try constant(.null, .reference("java/lang/Object", nullable: true)))
                let params = [JVMValueType.reference(plan.name, nullable: false)] + method.parameters + Array(repeating: JVMValueType.int, count: masks.count) + [.reference("java/lang/Object", nullable: true)]
                return JVMIntrinsicResult(value: try jdkCall(plan.name, "copy$default", params, method.result, arguments: arguments, resolved: program.expressionType(id)))
            }
            return JVMIntrinsicResult(value: try jdkCall(plan.name, "copy", method.parameters, method.result, receiver: object, arguments: values, resolved: program.expressionType(id)))
        }
        guard let receiver, let name else { return nil }
        let receiverSymbol = program.sema.bindings.identifierSymbol(for: receiver)
        let enumPlan = receiverSymbol.flatMap { program.classes[$0] }
        if let plan = enumPlan, plan.isEnum, ["values", "valueOf", "entries"].contains(name) {
            let params: [JVMValueType] = name == "valueOf" ? [.string] : []
            guard args.count == params.count, args.allSatisfy({ $0.label == nil && !$0.isSpread }) else { throw fail("Unsupported JVM enum static call.", id) }
            let result = name == "entries" ? program.enumEntriesField(plan).type : (name == "values" ? program.enumValuesField(plan).type : .reference(plan.name, nullable: false))
            return JVMIntrinsicResult(value: try jdkCall(plan.name, name == "entries" ? "getEntries" : name, params, result, arguments: args.map { try requireValue($0.expr) }))
        }
        if let semantic = program.sema.bindings.exprType(for: receiver), case let .classType(t) = program.sema.types.kind(of: semantic), program.sema.symbols.symbol(t.classSymbol)?.kind == .enumClass {
            if !arena.isExplicitCall(id), args.isEmpty, ["name", "ordinal"].contains(name) { return JVMIntrinsicResult(value: try jdkCall("java/lang/Enum", name, [], name == "name" ? .string : .int, receiver: requireValue(receiver))) }
            if name == "compareTo", args.count == 1 { return JVMIntrinsicResult(value: try jdkCall("java/lang/Enum", "compareTo", [.reference("java/lang/Enum", nullable: false)], .int, receiver: requireValue(receiver), arguments: [requireValue(args[0].expr)])) }
        }
        return nil
    }

    func destructuring(_ id: ExprID, names: [InternedString?], mutable: Bool, initializer: ExprID) throws {
        let object = try requireValue(initializer)
        for (i, name) in names.enumerated() {
            guard let name else { continue }
            guard let symbol = program.sema.bindings.destructuringComponentCallee(for: id, index: i), let method = program.methods[symbol] ?? program.textLibraryMethods[symbol]?.method else { throw fail("JVM destructuring requires registered components.", id) }
            let result: JVMValue
            if method.owner == "kotlin/text/MatchResult$Destructured" { result = try textMatchComponent(object, index: i) }
            else if program.textLibraryMethods[symbol]?.extensionReceiver != nil {
                guard let receiverType = method.parameters.first else { throw fail("JVM destructuring extension has no receiver parameter.", id) }
                let receiver = try convert(object, to: receiverType)
                result = try jdkCall(method.owner, method.name, method.parameters, method.result, arguments: [receiver])!
            }
            else { result = try jdkCall(method.owner, method.name, [], method.result, receiver: object, interface: method.isInterface)! }
            var local = Local(value: result, mutable: mutable)
            if mutable {
                let cell = try value(.reference("[" + result.type.descriptor, nullable: false))
                instructions.append(.newArray(result.type, count: try constant(.int(1), .int), result: cell))
                instructions.append(.arraySet(cell, try constant(.int(0), .int), result)); local.cell = cell
            }
            scopes[scopes.count - 1][name] = local
        }
    }

    func whenExpression(_ id: ExprID, subject: ExprID?, branches: [WhenBranch], fallback: ExprID?, discarded: Bool) throws -> JVMValue? {
        let snapshot = try subject.map(requireValue), type = try program.expressionType(id)
        let savedEvaluatedOperands = evaluatedOperands
        if let subject, let snapshot { evaluatedOperands[subject] = snapshot }
        defer { evaluatedOperands = savedEvaluatedOperands }
        let result = discarded || type == .unit ? nil : try value(type), end = label()
        scopes.append([:]); defer { scopes.removeLast() }
        if let name = arena.whenSubjectVarName(for: id), let snapshot { scopes[scopes.count - 1][name] = Local(value: snapshot, mutable: false) }
        var hasEnd = false, canTestNext = true
        func branchBody(_ body: ExprID) throws {
            let source = try expression(body, discarded: discarded)
            if !terminated {
                if let result, let source { instructions.append(.copy(try convert(source, to: result.type), result)) }
                jump(end); hasEnd = true
            }
        }
        for branch in branches {
            guard branch.guard_ == nil else { throw fail("JVM guarded when branches are unsupported.", id) }
            let selected = label(), next = label()
            var selectedReachable = false
            for condition in branch.conditions {
                let check: JVMValue
                if case let .isCheck(_, target, negated, _) = arena.expr(condition), let snapshot {
                    guard let semantic = program.sema.bindings.isCheckTargetType(for: condition) else { throw fail("Missing JVM when type test.", condition) }
                    check = try instanceCheckValue(snapshot, semantic: semantic, negated: negated, id: condition)
                    _ = target
                } else {
                    let tested = try expression(condition)
                    if terminated { canTestNext = false; break }
                    guard let tested else { throw fail("JVM when condition requires a value.", condition) }
                    let isMembershipCondition: Bool
                    switch arena.expr(condition) {
                    case .inExpr(_, _, _), .notInExpr(_, _, _): isMembershipCondition = true
                    default: isMembershipCondition = false
                    }
                    if let snapshot, !isMembershipCondition {
                        check = try value(.boolean)
                        if snapshot.type.referenceName != nil || tested.type.referenceName != nil {
                            instructions.append(.binary(.equal, try convert(snapshot, to: .reference("java/lang/Object", nullable: true)), try convert(tested, to: .reference("java/lang/Object", nullable: true)), check))
                        } else { instructions.append(.binary(.equal, snapshot, try convert(tested, to: snapshot.type), check)) }
                    } else {
                        guard tested.type == .boolean || snapshot == nil else { throw fail("JVM membership when conditions must produce Boolean.", condition) }
                        check = tested
                    }
                }
                let alternative = label()
                instructions.append(.jumpIfFalse(check, alternative)); jump(selected); selectedReachable = true; mark(alternative)
            }
            if canTestNext { jump(next) }
            if selectedReachable { mark(selected); try branchBody(branch.body) }
            if !canTestNext { break }
            mark(next)
        }
        if canTestNext, let fallback { try branchBody(fallback) }
        else if canTestNext, result != nil {
            let error = try constructJDK("java/lang/IllegalStateException", parameters: [.string], arguments: [constant(.string("No matching when branch"), .string)])
            instructions.append(.throwValue(error)); terminated = true
        } else if canTestNext { jump(end); hasEnd = true }
        if hasEnd { mark(end) }
        return result
    }
}
