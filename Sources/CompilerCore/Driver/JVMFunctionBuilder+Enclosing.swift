import Foundation

struct JVMAnonymousCapture {
    let field: JVMField
    var name: InternedString? = nil
    var local: JVMFunctionBuilder.Local? = nil
    var receiverSymbols: [SymbolID] = []
    var extensionReceiver = false
    var reifiedClass: SymbolID? = nil
    var reifiedNullable: SymbolID? = nil
    var reifiedMutableKind: SymbolID? = nil
}

extension JVMProgramBuilder {
    func outerField(_ plan: JVMClassPlan) throws -> JVMField? {
        guard plan.isInner, let outer = plan.outer else { return nil }
        return JVMField(owner: plan.name, name: "this$0", type: .reference(try className(outer), nullable: false), access: 0x1012)
    }
    func hiddenConstructorTypes(_ plan: JVMClassPlan) throws -> [JVMValueType] {
        try outerField(plan).map { [$0.type] } ?? []
    }
    func objectSuper(_ plan: JVMClassPlan) throws -> (method: JVMForeignMethod, binding: CallBinding?) {
        let binding = sema.bindings.constructorDelegationCallBinding(for: plan.symbol)
        if let binding, let method = methods[binding.chosenCallee] ?? context.jvmImports?.methods[binding.chosenCallee] ?? builtinMethod(binding.chosenCallee) { return (method, binding) }
        if plan.superclass == "java/lang/Object" { return (objectConstructor(), nil) }
        throw JVMFrontendError(message: "Missing JVM object superclass constructor binding.", range: plan.object?.range)
    }
    func emitAnonymousConstructor(_ plan: JVMClassPlan) throws -> JVMFunction {
        let method = plan.anonymousSuper!
        let params = plan.captures.map { $0.field.type } + method.parameters
        let b = try nominalBuilder(plan, name: "<init>", parameters: params)
        let inputs = Array(b.locals.dropFirst()), own = b.thisValue!
        for (capture, input) in zip(plan.captures, inputs) { b.instructions.append(.putField(capture.field, own, input)) }
        b.instructions.append(.foreignCall(method, receiver: own, arguments: Array(inputs.dropFirst(plan.captures.count)), result: nil))
        b.scopes = [[:]]
        try b.prepareEnclosingInstances()
        try emitClassDelegates(plan, builder: b, object: own)
        try emitInitializers(plan, builder: b, object: own)
        if !b.terminated { b.instructions.append(.returnValue(nil)) }
        var f = b.finish(constructor: true); f.access = plan.escapesInline ? 1 : 0; return f
    }
}

extension JVMFunctionBuilder {
    func enclosingInstance(_ symbol: SymbolID) throws -> JVMValue {
        if let value = contextualReceivers[symbol] ?? contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)] { return value }
        if let owner, owner.symbol == symbol, let thisValue, !beforeDelegation { return thisValue }
        throw fail("Missing JVM enclosing instance.")
    }
    func bindEnclosingInstance(_ plan: JVMClassPlan, value: JVMValue) throws {
        contextualReceivers[plan.symbol] = value
        contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: plan.symbol)] = value
        if let field = try program.outerField(plan), let outer = plan.outer, let parent = program.classes[outer] {
            let next = try self.value(field.type); instructions.append(.getField(field, value, next))
            try bindEnclosingInstance(parent, value: next)
        }
    }
    func prepareEnclosingInstances(_ target: JVMClassPlan? = nil) throws {
        guard let owner = target ?? owner, let own = thisValue else { return }
        try bindEnclosingInstance(owner, value: own)
        var captured: [InternedString: Local] = [:]
        var tokenClasses: [SymbolID: JVMValue] = [:], tokenNullables: [SymbolID: JVMValue] = [:], tokenMutableKinds: [SymbolID: JVMValue] = [:]
        for capture in owner.captures {
            let input = try value(capture.field.type); instructions.append(.getField(capture.field, own, input))
            if let name = capture.name, let template = capture.local {
                var local = template
                if template.cell != nil { local = Local(value: try value(template.value.type), mutable: template.mutable, cell: input, functionType: template.functionType, symbol: template.symbol) }
                else { local = Local(value: input, mutable: false, functionType: template.functionType, symbol: template.symbol) }
                local.delegateSymbol = template.delegateSymbol; local.lateName = template.lateName
                captured[name] = local
            }
            for symbol in capture.receiverSymbols { contextualReceivers[symbol] = input }
            if capture.extensionReceiver { extensionValue = input }
            if let symbol = capture.reifiedClass { tokenClasses[symbol] = input }
            if let symbol = capture.reifiedNullable { tokenNullables[symbol] = input }
            if let symbol = capture.reifiedMutableKind { tokenMutableKinds[symbol] = input }
        }
        for (symbol, klass) in tokenClasses {
            guard let nullable = tokenNullables[symbol], let mutableKind = tokenMutableKinds[symbol] else { throw fail("Missing anonymous object reified nullability or mutability capture.") }
            reifiedRuntimeTokens[symbol] = ReifiedRuntimeToken(klass: klass, nullable: nullable, mutableKind: mutableKind)
        }
        if !captured.isEmpty { scopes.insert(captured, at: 0) }
    }

    func anonymousObject(_ id: ExprID) throws -> JVMValue {
        guard case let .objectLiteral(_, decl?, range) = arena.expr(id), let symbol = program.sema.bindings.declSymbol(for: decl), let plan = program.classes[symbol] else { throw fail("Missing JVM anonymous object declaration.", id) }
        if plan.enclosingMethod == nil { plan.enclosingMethod = currentEnclosingMethod }
        plan.escapesInline = plan.escapesInline || declaration.isInline || !inlineStack.isEmpty
        let visible = localCaptureEnvironment()
        var used: Set<SymbolID> = []
        for i in arena.snapshot().expressions.indices {
            let exprID = ExprID(rawValue: Int32(i))
            guard let site = arena.exprRange(exprID), site.start.file == range.start.file, site.start.offset >= range.start.offset, site.end.offset <= range.end.offset else { continue }
            if let symbol = program.sema.bindings.identifierSymbol(for: exprID) { used.insert(symbol) }
            if let binding = program.sema.bindings.callableValueCallBinding(for: exprID), case let .localValue(symbol) = binding.target { used.insert(symbol) }
        }
        used.formUnion(localReferenceCaptureSymbols(in: id))
        var captures: [JVMAnonymousCapture] = [], values: [JVMValue] = []
        for (name, local) in visible.sorted(by: { context.interner.resolve($0.key) < context.interner.resolve($1.key) }) where local.symbol.map({ used.contains($0) }) ?? true {
            var source = local.cell ?? local.value, template = local
            if let symbol = local.symbol,
               let semantic = program.sema.bindings.capturedLocalType(for: symbol) ?? program.sema.symbols.propertyType(for: symbol) {
                let type = try erasedLocalStorageType(semantic)
                let storage = local.cell == nil ? type : (local.delegateSymbol == nil ? .reference("[" + type.descriptor, nullable: false) : source.type)
                source = try convert(source, to: storage)
                template = Local(value: JVMValue(slot: local.value.slot, type: type), mutable: local.mutable, cell: local.cell, functionType: local.functionType, symbol: local.symbol)
                template.delegateSymbol = local.delegateSymbol; template.lateName = local.lateName
            }
            let field = JVMField(owner: plan.name, name: "$capture" + String(captures.count), type: source.type, access: 0x1012)
            captures.append(JVMAnonymousCapture(field: field, name: name, local: template)); values.append(source)
        }
        var receivers = contextualReceivers
        if let owner, let thisValue, !beforeDelegation {
            receivers[owner.symbol] = thisValue
            receivers[SyntheticSymbolScheme.receiverParameterSymbol(for: owner.symbol)] = thisValue
        }
        var groups: [Int: [SymbolID]] = [:], receiverValues: [Int: JVMValue] = [:]
        for (symbol, input) in receivers where !beforeDelegation || input.slot != thisValue?.slot { groups[input.slot, default: []].append(symbol); receiverValues[input.slot] = input }
        if let extensionValue { groups[extensionValue.slot, default: []] += []; receiverValues[extensionValue.slot] = extensionValue }
        for slot in groups.keys.sorted() {
            var erased: JVMValueType?, conflict = false
            for symbol in groups[slot]! {
                guard let owner = SyntheticSymbolScheme.receiverParameterOwner(for: symbol),
                      let receiverType = program.sema.symbols.functionSignature(for: owner)?.receiverType else { continue }
                let type = try erasedLocalStorageType(receiverType)
                if erased == nil { erased = type } else if erased != type { conflict = true }
            }
            let fieldType = conflict ? JVMValueType.reference("java/lang/Object", nullable: false) : erased ?? receiverValues[slot]!.type
            let source = try convert(receiverValues[slot]!, to: fieldType), field = JVMField(owner: plan.name, name: "$receiver" + String(captures.count), type: fieldType, access: 0x1012)
            captures.append(JVMAnonymousCapture(field: field, receiverSymbols: groups[slot]!, extensionReceiver: slot == extensionValue?.slot)); values.append(source)
        }
        let tokenTypes = reifiedCaptureTypes(id, specialize: false)
        var needsClassReification = false
        for type in tokenTypes {
            if program.reifiedUse(type) != nil, try runtimeReifiedToken(type) == nil { needsClassReification = true }
            guard case let .typeParam(t) = program.sema.types.kind(of: type) else { continue }
            let token = try materializeReifiedToken(type)
            let klass = JVMField(owner: plan.name, name: "$type" + String(t.symbol.rawValue), type: token.klass.type, access: 0x1012)
            let nullable = JVMField(owner: plan.name, name: "$nullable" + String(t.symbol.rawValue), type: .boolean, access: 0x1012)
            let mutableKind = JVMField(owner: plan.name, name: "$mutableKind" + String(t.symbol.rawValue), type: .int, access: 0x1012)
            captures.append(JVMAnonymousCapture(field: klass, reifiedClass: t.symbol)); values.append(token.klass)
            captures.append(JVMAnonymousCapture(field: nullable, reifiedNullable: t.symbol)); values.append(token.nullable)
            captures.append(JVMAnonymousCapture(field: mutableKind, reifiedMutableKind: t.symbol)); values.append(token.mutableKind)
        }
        if plan.anonymousSuper == nil { plan.captures = captures }
        else if plan.captures.count == captures.count {
            // Every instantiation shares the lexical class layout, even when
            // a caller supplies a more specific type during AST inlining.
            for i in captures.indices { values[i] = try convert(values[i], to: plan.captures[i].field.type) }
            captures = plan.captures
        }
        guard plan.captures.map({ $0.field.type }) == captures.map({ $0.field.type }) else { throw fail("JVM anonymous object capture shape changed during inline expansion.", id) }
        let selected = try program.objectSuper(plan)
        let sourceArgs = plan.object!.superTypeConstructorArgs
        let sourceParameters = selected.binding.flatMap { program.sourceParameters[$0.chosenCallee] }
        let allocatedName: String
        if !plan.escapesInline { allocatedName = plan.name }
        else { allocatedName = plan.name + "$" + String(program.nextClosure); program.nextClosure += 1 }
        let own = try value(.reference(allocatedName, nullable: false))
        instructions.append(.allocate(allocatedName, own)); pendingAllocations.append(own)
        defer { pendingAllocations.removeLast() }
        let parent = program.classes.values.first { $0.name == selected.method.owner }
        let outer = try parent?.isInner == true ? [enclosingInstance(parent!.outer!)] : []
        let ordered = try arguments(sourceArgs, binding: selected.binding, parameters: Array(selected.method.parameters.dropFirst(outer.count)), declarations: sourceParameters, id: id)
        var superMethod = selected.method, superArgs = outer + ordered.values
        if ordered.masks.contains(where: { $0 != 0 }) {
            superArgs += try maskArguments(ordered.masks, constructor: true)
            let types = superArgs.map(\.type)
            superMethod = JVMForeignMethod(owner: superMethod.owner, name: "<init>", descriptor: "(" + types.map(\.descriptor).joined() + ")V", parameters: types, result: superMethod.result, isStatic: false, isInterface: false, isAbstract: false)
        }
        plan.anonymousSuper = superMethod
        values += superArgs
        guard values.reduce(1, { $0 + $1.type.width }) <= 255 else { throw fail("JVM anonymous constructor slot limit exceeded.", id) }
        let parameters = values.map(\.type), descriptor = "(" + parameters.map(\.descriptor).joined() + ")V"
        if allocatedName != plan.name {
            let receiver = JVMValue(slot: 0, type: own.type)
            var locals = [receiver], slot = 1
            for type in parameters { locals.append(JVMValue(slot: slot, type: type)); slot += type.width }
            let parent = JVMForeignMethod(owner: plan.name, name: "<init>", descriptor: descriptor, parameters: parameters, result: .reference(plan.name, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
            let ctor = program.rawFunction(allocatedName, name: "<init>", parameters: parameters, result: .unit, access: 1, locals: locals, instructions: [.foreignCall(parent, receiver: receiver, arguments: Array(locals.dropFirst()), result: nil), .returnValue(nil)], constructor: true)
            program.closureClasses.append(program.rawClass(allocatedName, superclass: plan.name, access: 0x1031, functions: [ctor]))
        }
        if needsClassReification {
            let marker = JVMForeignMethod(owner: "kotlin/jvm/internal/Intrinsics", name: "needClassReification", descriptor: "()V", parameters: [], result: .unit, isStatic: true, isInterface: false, isAbstract: false)
            instructions.append(.foreignCall(marker, receiver: nil, arguments: [], result: nil))
        }
        let method = JVMForeignMethod(owner: allocatedName, name: "<init>", descriptor: descriptor, parameters: parameters, result: own.type, isStatic: false, isInterface: false, isAbstract: false)
        instructions.append(.foreignCall(method, receiver: own, arguments: values, result: nil))
        return own
    }
}
