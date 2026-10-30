import Foundation

private struct JVMValueClassInfo {
    let name: String
    let underlying: JVMValueType
    let field: JVMField
    let sourceField: JVMField
}

extension JVMProgramBuilder {
    /// Source IR stays boxed; ABI entry points adapt to Kotlin's unboxed JVM ABI.
    func lowerValueClasses(_ input: JVMProgram) throws -> JVMProgram {
        var output = input
        let fileFacades = Set([input.internalClassName] + input.classes.filter(\.isFileFacade).map(\.name))
        var values: [String: JVMValueClassInfo] = [:]
        var valueSignatures: [String: (underlying: String, input: String, parameters: [String])] = [:]
        var callableSignatures: [String: String] = [:]
        var fields: [String: JVMField] = [:]
        for plan in classes.values where plan.isValue {
            guard let declaration = plan.declaration, declaration.primaryConstructorParams.count == 1,
                  let field = plan.properties.first(where: { $0.2.name == context.interner.resolve(declaration.primaryConstructorParams[0].name) })?.2.field else {
                throw JVMFrontendError(message: "JVM value classes require one stored primary parameter.", range: plan.declaration?.range)
            }
            fields[plan.name] = field
        }
        func erased(_ type: JVMValueType, visiting: Set<String> = []) throws -> JVMValueType {
            guard let name = type.referenceName, let field = fields[name] else { return type }
            guard !visiting.contains(name) else { throw JVMFrontendError(message: "Recursive JVM value-class storage is not supported.") }
            let underlying = try erased(field.type, visiting: visiting.union([name]))
            if !type.isNullable { return underlying }
            if let reference = underlying.referenceName, !underlying.isNullable { return .reference(reference, nullable: true) }
            return type
        }
        for plan in classes.values where plan.isValue {
            let source = fields[plan.name]!, underlying = try erased(source.type)
            var field = JVMField(owner: source.owner, name: source.name, type: underlying, access: source.access)
            field.annotations = source.annotations; field.constantValue = source.constantValue
            values[plan.name] = JVMValueClassInfo(name: plan.name, underlying: underlying, field: field, sourceField: source)
            let semantic = sema.symbols.valueClassUnderlyingType(for: plan.symbol)!
            valueSignatures[plan.name] = (try signatureType(semantic), try signatureType(semantic, parameterPosition: true), plan.declaration!.typeParams.map { context.interner.resolve($0.name) })
        }
        var resolvedSignatures: Set<String> = []
        func resolveSignature(_ name: String) {
            guard resolvedSignatures.insert(name).inserted, let info = values[name],
                  info.sourceField.type.descriptor != info.underlying.descriptor,
                  let inner = info.sourceField.type.referenceName, values[inner] != nil else { return }
            resolveSignature(inner)
            let logical = valueSignatures[name]!
            var result = rawFunction(name, name: "$signature", parameters: [], result: info.sourceField.type, access: 9, locals: [], instructions: [])
            result.genericSignature = "()" + logical.underlying
            let reference = JVMFunctionReference(name: "$signature", parameters: [], result: info.underlying)
            let outputSignature = adaptedValueSignature(result, reference: reference, receiverOffset: 0, values: valueSignatures).map { String($0.dropFirst(2)) } ?? info.underlying.descriptor
            var input = rawFunction(name, name: "$signature", parameters: [info.sourceField.type], result: .unit, access: 9, locals: [], instructions: [])
            input.genericSignature = "(" + logical.underlying + ")V"
            let inputRef = JVMFunctionReference(name: "$signature", parameters: [info.underlying], result: .unit)
            let inputSignature = adaptedValueSignature(input, reference: inputRef, receiverOffset: 0, values: valueSignatures).map { String($0.dropFirst().dropLast(2)) } ?? info.underlying.descriptor
            valueSignatures[name] = (outputSignature, inputSignature, logical.parameters)
        }
        for name in values.keys { resolveSignature(name) }
        func physical(_ type: JVMValueType) -> JVMValueType {
            guard let name = type.referenceName, let value = values[name] else { return type }
            if !type.isNullable { return value.underlying }
            if let reference = value.underlying.referenceName, !value.underlying.isNullable { return .reference(reference, nullable: true) }
            return type
        }
        func unsignedResult(_ type: JVMValueType) -> JVMSuspendValueResult? {
            guard case let .unsignedArray(_, nullable) = type else { return nil }
            return JVMSuspendValueResult(boxed: .reference(type.unsignedName!, nullable: nullable), underlying: .reference(type.descriptor, nullable: nullable), adapterOwner: nullable ? facadeName + "$" + String(type.unsignedName!.split(separator: "/").last!) + "Adapters" : nil)
        }
        func element(_ type: JVMValueType) -> String {
            if type.referenceName == "kotlin/Result" { return "_" }
            if let name = type.unsignedName { return "L" + name.replacingOccurrences(of: "/", with: ".") + (type.isNullable ? "?" : "") + ";" }
            guard let name = type.referenceName, values[name] != nil else { return "_" }
            return "L" + name.replacingOccurrences(of: "/", with: ".").replacingOccurrences(of: "$", with: ".") + (type.isNullable ? "?" : "") + ";"
        }
        func builder(_ owner: String, _ name: String, _ params: [JVMValueType], _ result: JVMValueType, staticBody: Bool) throws -> JVMFunctionBuilder {
            let plan = classes.values.first { $0.name == owner }
            let range = ast.files.first { context.sourceManager.origin(of: $0.fileID) == .user }!.range!
            let declaration = FunDecl(range: range, name: context.interner.intern(name), modifiers: [], valueParams: params.indices.map { ValueParamDecl(name: context.interner.intern("p\($0)"), type: nil) }, body: .unit)
            let b = JVMFunctionBuilder(program: self, declaration: declaration, reference: JVMFunctionReference(name: name, parameters: params, result: result), owner: plan)
            b.isStaticBody = staticBody
            try b.prepareParameters()
            return b
        }
        func convert(_ source: JVMValue, to target: JVMValueType, b: JVMFunctionBuilder) throws -> JVMValue {
            if source.type == target { return source }
            let fromValue = source.type.referenceName.flatMap { values[$0] }
            let toValue = target.referenceName.flatMap { values[$0] }
            if let info = toValue, physical(target) != target {
                let method = JVMForeignMethod(owner: info.name, name: "box-impl", descriptor: "(" + info.underlying.descriptor + ")L" + info.name + ";", parameters: [info.underlying], result: .reference(info.name, nullable: false), isStatic: true, isInterface: false, isAbstract: false)
                let result = try b.value(target)
                let end = b.label()
                if target.isNullable {
                    let check = try b.value(.boolean), null = try b.constant(.null, source.type), nonnull = b.label()
                    b.instructions += [.referenceCompare(.equal, source, null, check), .jumpIfFalse(check, nonnull), .constant(.null, result)]
                    b.jump(end); b.mark(nonnull)
                }
                b.instructions.append(.foreignCall(method, receiver: nil, arguments: [try b.convert(source, to: info.underlying)], result: result))
                if target.isNullable { b.mark(end) }
                return result
            }
            if let info = fromValue, physical(source.type) != source.type {
                let result = try b.value(target), end = b.label()
                if source.type.isNullable {
                    let check = try b.value(.boolean), null = try b.constant(.null, source.type), nonnull = b.label()
                    b.instructions += [.referenceCompare(.equal, source, null, check), .jumpIfFalse(check, nonnull), .constant(.null, result)]
                    b.jump(end); b.mark(nonnull)
                }
                let method = JVMForeignMethod(owner: info.name, name: "unbox-impl", descriptor: "()" + info.underlying.descriptor, parameters: [], result: info.underlying, isStatic: false, isInterface: false, isAbstract: false)
                b.instructions.append(.foreignCall(method, receiver: source, arguments: [], result: result))
                if source.type.isNullable { b.mark(end) }
                return result
            }
            return try b.convert(source, to: target)
        }
        func hidden(_ original: JVMFunction) -> JVMFunction {
            var f = original; f.isSynthetic = true; f.access = (f.access ?? (f.isPrivate ? 10 : 9)) | 0x1000
            return f
        }
        func finish(_ b: JVMFunctionBuilder, original: JVMFunction, reference: JVMFunctionReference, offset: Int = 0) -> JVMFunction {
            var result = original; result.reference = reference; result.locals = b.locals; result.instructions = b.instructions
            result.handlers = b.handlers; result.parameterCount = reference.parameters.count + (b.isStaticBody ? 0 : 1)
            result.access = (original.access ?? (original.isPrivate ? 2 : 1)) & ~UInt16(0x0408) | (b.isStaticBody ? 8 : 0)
            result.genericSignature = adaptedValueSignature(original, reference: reference, receiverOffset: offset, values: valueSignatures); result.metadataParameterOffset = offset
            result.sourceName = original.sourceName ?? original.reference.name
            if offset > 0 { result.parameterAnnotations = Array(repeating: [], count: offset) + original.parameterAnnotations }
            result.isConstructor = false; result.isAbstract = false
            return result
        }
        func bridge(_ original: JVMFunction, owner: String, properties: [JVMProperty], baseName: String? = nil) throws -> [JVMFunction] {
            let sourcePlan = classes.values.first { $0.name == owner }
            // Captures in lifted closures keep the boxed internal IR layout.
            guard fileFacades.contains(owner) || sourcePlan != nil else { return [original] }
            if original.isConstructor && sourcePlan?.isAnonymous == true { return [original] }
            let ref = original.reference
            let storageGetter = values[owner].map { info in properties.contains { $0.name == info.field.name && $0.getter.name == ref.name && $0.getter.descriptor == ref.descriptor } } ?? false
            let ownValue = storageGetter ? nil : values[owner]
            if ref.name == "<clinit>" || ref.name.hasPrefix("$lambda") || ref.name.hasPrefix("$access") || ref.name.hasPrefix("$default") { return [original] }
            if values[owner] != nil && original.isConstructor { return [hidden(original)] }
            let isStatic = (original.access ?? 8) & 8 != 0
            let isDefault = ref.name.hasSuffix("$default")
            let affected = original.jvmName != nil || ownValue != nil && !original.isConstructor || (ref.parameters + [ref.result]).contains { $0.unsignedName != nil || $0.referenceName.flatMap { values[$0] } != nil }
            guard affected else { return [original] }
            var name = ref.name.components(separatedBy: "$unsigned$")[0]
            let visibleName = original.sourceName ?? name
            let parameters = ref.parameters.map(physical)
            // Coroutine transport always carries the logical boxed result.
            let result = original.isSuspend ? ref.result : physical(ref.result)
            if !original.isConstructor {
                if let baseName { name = baseName + "$default" }
                else {
                    let hashArguments = ref.parameters.map(element).joined() + (original.isSuspend ? "_" : "")
                    let resultElement = fileFacades.contains(owner) ? "_" : element(ref.result)
                    let hash = hashArguments + (resultElement == "_" ? "" : ":" + resultElement)
                    if hashArguments.contains("L") || resultElement != "_" { name += "-" + JVMNameHash.suffix(hash) }
                    else if ownValue != nil { name += "-impl" }
                    if let explicit = original.jvmName { name = explicit }
                }
            }
            var physicalParameters = (ownValue != nil && !isStatic && !original.isConstructor ? [ownValue!.underlying] : []) + parameters
            let staticBridge = isStatic || ownValue != nil && !original.isConstructor
            var physicalRef = JVMFunctionReference(name: name, parameters: physicalParameters, result: result, owner: owner, ownerIsInterface: classes.values.first { $0.name == owner }?.isInterface == true)
            physicalRef.isSuspend = original.isSuspend
            if name == ref.name && physicalParameters == ref.parameters && result == ref.result && ownValue == nil {
                var exported = original
                if original.isConstructor, ref.parameters.contains(where: { $0.unsignedName != nil }) {
                    let marker = JVMValueType.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)
                    if ref.parameters.last != marker {
                        let params = ref.parameters + [marker]
                        guard params.reduce(1, { $0 + $1.width }) <= 255 else { throw JVMFrontendError(message: "JVM unsigned constructor parameter slot limit exceeded.") }
                        let ctor = try builder(owner, "<init>", params, .unit, staticBody: false)
                        let target = JVMForeignMethod(owner: owner, name: "<init>", descriptor: ref.descriptor, parameters: ref.parameters, result: .reference(owner, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
                        ctor.instructions = [.foreignCall(target, receiver: ctor.thisValue, arguments: Array(ctor.locals.dropFirst().prefix(ref.parameters.count)), result: nil), .returnValue(nil)]
                        var adapter = ctor.finish(constructor: true); adapter.isSynthetic = true; adapter.access = 0x1001
                        exported.metadataDescriptor = "(" + params.map(\.descriptor).joined() + ")V"
                        return [exported, adapter]
                    }
                }
                if original.isSuspend { exported.suspendValueResult = unsignedResult(ref.result) }
                if original.isSuspend, physical(ref.result) != ref.result, physical(ref.result).referenceName != nil {
                    exported.suspendValueResult = JVMSuspendValueResult(boxed: ref.result, underlying: physical(ref.result))
                }
                return [exported]
            }
            let b = try builder(owner, name, physicalParameters, result, staticBody: staticBridge)
            let inputs = Array(b.locals.prefix(b.reference.parameters.count + (staticBridge ? 0 : 1)))
            var index = staticBridge ? 0 : 1
            let receiver: JVMValue?
            if let ownValue, !isStatic && !original.isConstructor { receiver = try convert(inputs[index], to: .reference(ownValue.name, nullable: false), b: b); index += 1 }
            else { receiver = isStatic ? nil : b.thisValue }
            var args: [JVMValue] = []
            for (input, logical) in zip(inputs.dropFirst(index), ref.parameters) { args.append(try convert(input, to: logical, b: b)) }
            let returned = ref.result == .unit ? nil : try b.value(ref.result)
            var target = JVMForeignMethod(owner: owner, name: ref.name, descriptor: ref.descriptor, parameters: ref.parameters, result: ref.result, isStatic: isStatic, isInterface: physicalRef.ownerIsInterface, isAbstract: original.isAbstract, isSpecial: original.isPrivate && !isStatic)
            target.isSuspend = original.isSuspend
            var inlineContinuation = original.inlineContinuation
            if original.isInline && !original.isAbstract {
                // Export the actual body so Kotlin's bytecode inliner can
                // substitute lambda invokes and preserve non-local returns.
                var mapping: [Int: JVMValue] = [:]
                let sourceInputs = (receiver.map { [$0] } ?? []) + args
                for (local, input) in zip(original.locals.prefix(original.parameterCount), sourceInputs) { mapping[local.slot] = input }
                for local in original.locals.dropFirst(original.parameterCount) { mapping[local.slot] = try b.value(local.type) }
                if let continuation = original.inlineContinuation { inlineContinuation = mapping[continuation.slot] }
                let labelOffset = b.nextLabel
                b.nextLabel += original.instructions.compactMap(\.labelNumber).max().map { $0 + 1 } ?? 0
                for instruction in original.instructions {
                    let mapped = instruction.mappingValues { mapping[$0.slot]! }.offsettingLabels(by: labelOffset)
                    if case let .returnValue(value) = mapped {
                        b.instructions.append(.returnValue(try value.map { try convert($0, to: result, b: b) }))
                    } else { b.instructions.append(mapped) }
                }
                b.handlers = original.handlers.map { JVMExceptionHandler(start: $0.start + labelOffset, end: $0.end + labelOffset, handler: $0.handler + labelOffset, type: $0.type) }
            } else if !original.isAbstract {
                b.instructions.append(.foreignCall(target, receiver: receiver, arguments: args, result: returned))
                b.instructions.append(.returnValue(try returned.map { try convert($0, to: result, b: b) }))
            }
            var adapter = finish(b, original: original, reference: physicalRef, offset: ownValue != nil && !isStatic ? 1 : 0)
            if original.isSuspend, let name = ref.result.referenceName, values[name] != nil,
               physical(ref.result) != ref.result, physical(ref.result).referenceName != nil {
                adapter.suspendValueResult = JVMSuspendValueResult(boxed: ref.result, underlying: physical(ref.result))
            }
            if original.isSuspend, let representation = unsignedResult(ref.result) { adapter.suspendValueResult = representation }
            adapter.inlineContinuation = inlineContinuation
            adapter.sourceName = visibleName
            adapter.isConstructor = original.isConstructor
            adapter.isAbstract = original.isAbstract
            if original.isAbstract {
                adapter.instructions = []
                adapter.access = (original.access ?? 0x0401)
                // Boxed source calls dispatch through this default adapter to
                // the public unboxed contract, including external implementers.
                let back = try builder(owner, ref.name, ref.parameters, ref.result, staticBody: false)
                var arguments: [JVMValue] = []
                for (input, target) in zip(back.locals.dropFirst(), physicalParameters) { arguments.append(try convert(input, to: target, b: back)) }
                let raw = result == .unit ? nil : try back.value(result)
                var method = JVMForeignMethod(owner: owner, name: name, descriptor: physicalRef.descriptor, parameters: physicalParameters, result: result, isStatic: false, isInterface: physicalRef.ownerIsInterface, isAbstract: true)
                method.isSuspend = original.isSuspend
                back.instructions.append(.foreignCall(method, receiver: back.thisValue, arguments: arguments, result: raw))
                back.instructions.append(.returnValue(try raw.map { try convert($0, to: ref.result, b: back) }))
                var boxed = hidden(original); boxed.locals = back.locals; boxed.instructions = back.instructions; boxed.access = 0x1001; boxed.isAbstract = false
                return [boxed, adapter]
            }
            var additions = [hidden(original), adapter]
            if let ownValue, !isStatic, !original.isConstructor,
               classes.values.first(where: { $0.name == owner })?.methods.contains(where: { $0.1.name == ref.name && $0.1.descriptor == ref.descriptor && $0.0.modifiers.contains(.override) }) == true {
                let forward = try builder(owner, name, parameters, result, staticBody: false)
                let unboxed = try convert(forward.thisValue!, to: ownValue.underlying, b: forward)
                let returned = result == .unit ? nil : try forward.value(result)
                forward.instructions += [.call(physicalRef, [unboxed] + Array(forward.locals.dropFirst().prefix(parameters.count)), returned), .returnValue(returned)]
                var dispatch = forward.finish(); dispatch.isSuspend = original.isSuspend; dispatch.suspendValueResult = adapter.suspendValueResult; dispatch.access = 0x1011; dispatch.isSynthetic = true; additions.append(dispatch)
            }
            if original.isConstructor {
                // Kotlin adds the marker for value-class constructor parameters,
                // even when every source argument is explicit.
                adapter.access = 2; adapter.metadataDescriptor = "(" + (physicalParameters + [.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)]).map(\.descriptor).joined() + ")V"; additions[1] = adapter
                let marker: JVMValueType = .reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)
                if physicalParameters.last?.referenceName != marker.referenceName {
                    physicalParameters.append(marker)
                    let c = try builder(owner, "<init>", physicalParameters, .unit, staticBody: false)
                    let method = JVMForeignMethod(owner: owner, name: "<init>", descriptor: physicalRef.descriptor, parameters: parameters, result: .reference(owner, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
                    c.instructions += [.foreignCall(method, receiver: c.thisValue, arguments: Array(c.locals.dropFirst().prefix(parameters.count)), result: nil), .returnValue(nil)]
                    var exposed = c.finish(constructor: true); exposed.access = 0x1001; exposed.isSynthetic = true
                    exposed.annotations = original.annotations; exposed.parameterAnnotations = original.parameterAnnotations + [[]]
                    additions.append(exposed)
                } else { additions[1].access = 0x1001; additions[1].isSynthetic = true }
            }
            _ = isDefault
            return additions
        }
        func transform(_ functions: [JVMFunction], owner: String, properties: inout [JVMProperty]) throws -> [JVMFunction] {
            var result: [JVMFunction] = [], defaultNames: [String: String] = [:]
            for f in functions where !f.reference.name.hasSuffix("$default") {
                let functions = try bridge(f, owner: owner, properties: properties)
                if let exposed = functions.last(where: { !$0.isSynthetic }) {
                    defaultNames[f.reference.name + f.reference.descriptor] = exposed.reference.name
                    callableSignatures[owner + "." + f.reference.name + f.reference.descriptor] = exposed.reference.name + (exposed.metadataDescriptor ?? (exposed.isSuspend ? exposed.reference.suspendABI.descriptor : exposed.reference.descriptor))
                }
                if let exposed = functions.last(where: { !$0.isSynthetic }) {
                    for i in properties.indices {
                        func reference(_ original: JVMForeignMethod) -> JVMForeignMethod {
                            JVMForeignMethod(owner: owner, name: exposed.reference.name, descriptor: exposed.reference.descriptor, parameters: exposed.reference.parameters, result: exposed.reference.result, isStatic: (exposed.access ?? 0) & 8 != 0, isInterface: original.isInterface, isAbstract: exposed.isAbstract)
                        }
                        if properties[i].getter.name == f.reference.name && properties[i].getter.descriptor == f.reference.descriptor { properties[i].getter = reference(properties[i].getter) }
                        if let setter = properties[i].setter, setter.name == f.reference.name && setter.descriptor == f.reference.descriptor { properties[i].setter = reference(setter) }
                    }
                }
                result += functions
            }
            for f in functions where f.reference.name.hasSuffix("$default") {
                let base = String(f.reference.name.dropLast(8))
                let target = functions.first { candidate in
                    guard candidate.reference.name == base else { return false }
                    let dispatch = (candidate.access ?? (fileFacades.contains(owner) ? 8 : 0)) & 8 == 0 ? 1 : 0
                    let parameters = candidate.reference.parameters
                    return f.reference.parameters.count == dispatch + parameters.count + (candidate.isSuspend ? 1 : 0) + (parameters.count - (candidate.kotlinReceiver == nil ? 0 : 1) + 31) / 32 + 1 && Array(f.reference.parameters.dropFirst(dispatch).prefix(parameters.count)) == parameters
                }
                var bridged = try bridge(f, owner: owner, properties: properties, baseName: target.flatMap { defaultNames[$0.reference.name + $0.reference.descriptor] })
                if let target, target.isSuspend, physical(target.reference.result) != target.reference.result,
                   physical(target.reference.result).referenceName != nil {
                    let representation = JVMSuspendValueResult(boxed: target.reference.result, underlying: physical(target.reference.result))
                    if bridged.count > 1 || f.inlineContinuation != nil { bridged[bridged.count - 1].suspendValueResult = representation }
                    else { bridged[0].forwardedSuspendValueResult = representation }
                }
                if let target, target.isSuspend, let representation = unsignedResult(target.reference.result) {
                    if bridged.count > 1 || f.inlineContinuation != nil { bridged[bridged.count - 1].suspendValueResult = representation }
                    else { bridged[0].forwardedSuspendValueResult = representation }
                }
                result += bridged
            }
            return result
        }
        for i in output.classes.indices where values[output.classes[i].name] != nil {
            let name = output.classes[i].name
            output.classes[i].functions += try valueSemantics(classes.values.first { $0.name == name }!, existing: output.classes[i].functions)
        }
        output.functions = try transform(output.functions, owner: output.internalClassName, properties: &output.properties)
        for i in output.classes.indices {
            output.classes[i].functions = try transform(output.classes[i].functions, owner: output.classes[i].name, properties: &output.classes[i].properties)
        }
        var constructorTargets: [String: [JVMValueType]] = [:]
        // The validating boxed constructor is private to source IR. The ABI's
        // box-impl uses a separate storage-only constructor and never runs init.
        for i in output.classes.indices {
            guard let info = values[output.classes[i].name] else { continue }
            let plan = classes.values.first { $0.name == info.name }!
            let originalConstructors = output.classes[i].functions.filter(\.isConstructor)
            var reserved = Set(originalConstructors.map { $0.reference.descriptor })
            reserved.insert("(" + info.underlying.descriptor + ")V")
            for index in output.classes[i].functions.indices where output.classes[i].functions[index].isConstructor {
                var ctor = output.classes[i].functions[index]
                let original = ctor.reference
                if original.parameters != [info.underlying] {
                    ctor.access = 0x1001; ctor.isSynthetic = true
                    output.classes[i].functions[index] = ctor
                    continue
                }
                var params = original.parameters + [.boolean]
                while reserved.contains("(" + params.map(\.descriptor).joined() + ")V") { params.append(.boolean) }
                let descriptor = "(" + params.map(\.descriptor).joined() + ")V"
                reserved.insert(descriptor)
                constructorTargets[info.name + original.descriptor] = params
                let insertedSlot = 1 + original.parameters.reduce(0) { $0 + $1.width }
                let count = params.count - original.parameters.count
                func shift(_ value: JVMValue) -> JVMValue { JVMValue(slot: value.slot >= insertedSlot ? value.slot + count : value.slot, type: value.type) }
                ctor.instructions = ctor.instructions.map { $0.mappingValues(shift) }
                let prefix = original.parameters.count + 1
                ctor.locals = Array(ctor.locals.prefix(prefix)) + (0..<count).map { JVMValue(slot: insertedSlot + $0, type: .boolean) } + ctor.locals.dropFirst(prefix).map(shift)
                ctor.reference = JVMFunctionReference(name: "<init>", parameters: params, result: .unit)
                ctor.parameterCount += count; ctor.genericSignature = nil; ctor.access = 0x1001; ctor.isSynthetic = true
                output.classes[i].functions[index] = ctor
            }
            let storage = try builder(info.name, "<init>", [info.underlying], .unit, staticBody: false)
            storage.instructions = [.foreignCall(objectConstructor(), receiver: storage.thisValue, arguments: [], result: nil), .putField(info.field, storage.thisValue!, storage.locals[1]), .returnValue(nil)]
            var storageFunction = storage.finish(constructor: true); storageFunction.access = 2; storageFunction.isSynthetic = true; storageFunction.checksParameters = false
            output.classes[i].functions.append(storageFunction)
            let box = try builder(info.name, "box-impl", [info.underlying], .reference(info.name, nullable: false), staticBody: true)
            let boxed = try box.value(box.reference.result)
            let real = JVMForeignMethod(owner: info.name, name: "<init>", descriptor: "(" + info.underlying.descriptor + ")V", parameters: [info.underlying], result: boxed.type, isStatic: false, isInterface: false, isAbstract: false)
            box.instructions += [.allocate(info.name, boxed), .foreignCall(real, receiver: boxed, arguments: [box.locals[0]], result: nil), .returnValue(boxed)]
            var boxFunction = box.finish(); boxFunction.access = 0x1019; boxFunction.checksParameters = false
            output.classes[i].functions.append(boxFunction)
            let unbox = try builder(info.name, "unbox-impl", [], info.underlying, staticBody: false)
            let unboxed = try unbox.value(info.underlying)
            unbox.instructions = [.getField(info.field, unbox.thisValue!, unboxed), .returnValue(unboxed)]
            var unboxFunction = unbox.finish(); unboxFunction.access = 0x1011; unboxFunction.isSynthetic = true
            output.classes[i].functions.append(unboxFunction)
            for (symbol, declaration, _) in plan.constructors {
                let method = methods[symbol]!
                guard let source = originalConstructors.first(where: { $0.reference.parameters == method.parameters }) else { throw JVMFrontendError(message: "Missing JVM value-class constructor body.") }
                let variants = [source] + originalConstructors.filter { $0.reference.parameters == source.reference.parameters + Array(repeating: .int, count: (declaration.valueParams.count + 31) / 32) + [.reference("kotlin/jvm/internal/DefaultConstructorMarker", nullable: true)] && declaration.valueParams.contains(where: \.hasDefaultValue) }
                for variant in variants {
                    let isDefault = variant.reference.descriptor != source.reference.descriptor
                    let name = "constructor-impl" + (isDefault ? "$default" : "")
                    let params = variant.reference.parameters.map(physical)
                    let create = try builder(info.name, name, params, info.underlying, staticBody: true)
                    let args = try zip(create.locals, variant.reference.parameters).map { try convert($0.0, to: $0.1, b: create) }
                    let object = try create.value(.reference(info.name, nullable: false))
                    let target = JVMForeignMethod(owner: info.name, name: "<init>", descriptor: variant.reference.descriptor, parameters: variant.reference.parameters, result: object.type, isStatic: false, isInterface: false, isAbstract: false)
                    create.instructions += [.allocate(info.name, object), .foreignCall(target, receiver: object, arguments: args, result: nil)]
                    let returned = try convert(object, to: info.underlying, b: create)
                    create.instructions.append(.returnValue(returned))
                    var factory = source
                    factory.reference = create.reference; factory.locals = create.locals; factory.instructions = create.instructions; factory.handlers = create.handlers
                    factory.isConstructor = false; factory.isValueConstructor = !isDefault; factory.isSynthetic = isDefault
                    factory.parameterCount = params.count; factory.access = access(declaration.modifiers) | 8 | (isDefault ? 0x1000 : 0)
                    factory.checksParameters = false; factory.metadataDescriptor = nil
                    factory.parameterNames = declaration.valueParams.map { context.interner.resolve($0.name) }
                    factory.genericSignature = nil
                    if !isDefault {
                        let returnSignature = info.underlying.referenceName?.hasPrefix("[") == true ? info.underlying.descriptor : valueSignatures[info.name]!.underlying
                        let virtual = JVMFunctionReference(name: name, parameters: params, result: .unit)
                        let adapted = adaptedValueSignature(source, reference: virtual, receiverOffset: 0, values: valueSignatures)
                        if let adapted, let close = adapted.lastIndex(of: ")") {
                            factory.genericSignature = (output.classes[i].typeParameters.isEmpty ? "" : "<" + output.classes[i].typeParameters.map(\.signature).joined() + ">") + String(adapted[...close]) + (returnSignature.hasPrefix("T") ? info.underlying.descriptor : returnSignature)
                        }
                        callableSignatures[info.name + ".<init>" + source.reference.descriptor] = name + factory.reference.descriptor
                    }
                    output.classes[i].functions.append(factory)
                }
            }
            let equality = try builder(info.name, "equals-impl0", [info.underlying, info.underlying], .boolean, staticBody: true)
            let equal = try equality.value(.boolean)
            if info.underlying == .float || info.underlying == .double {
                let compared = try equality.jdkCall(info.underlying == .float ? "java/lang/Float" : "java/lang/Double", "compare", [info.underlying, info.underlying], .int, arguments: Array(equality.locals.prefix(2)))!
                equality.instructions.append(.binary(.equal, compared, try equality.constant(.int(0), .int), equal))
            } else { equality.instructions.append(.binary(.equal, equality.locals[0], equality.locals[1], equal)) }
            equality.instructions.append(.returnValue(equal))
            var equalityFunction = equality.finish(); equalityFunction.access = 0x1019; equalityFunction.isSynthetic = true
            output.classes[i].functions.append(equalityFunction)
            output.classes[i].annotations.append(JVMAnnotation(descriptor: "Lkotlin/jvm/JvmInline;", visible: true))
        }
        func calls(_ source: JVMFunction) throws -> JVMFunction {
            var f = source
            let b = try builder(source.owner ?? input.internalClassName, "$adapt", [], .unit, staticBody: true)
            b.locals = source.locals
            b.nextSlot = source.locals.map { $0.slot + $0.type.width }.max() ?? 0
            b.nextLabel = source.instructions.compactMap(\.labelNumber).max().map { $0 + 1 } ?? 0
            for instruction in source.instructions {
                switch instruction {
                case let .callableSignature(owner, name, descriptor, result):
                    b.instructions.append(.constant(.string(callableSignatures[owner + "." + name + descriptor] ?? name + descriptor), result))
                case let .foreignCall(method, receiver, args, result) where method.isConstructor && !(source.reference.name == "box-impl" && method.owner == source.owner):
                    if let params = constructorTargets[method.owner + method.descriptor] {
                        let extra = try params.dropFirst(args.count).map { _ in try b.constant(.boolean(false), .boolean) }
                        let target = JVMForeignMethod(owner: method.owner, name: "<init>", descriptor: "(" + params.map(\.descriptor).joined() + ")V", parameters: params, result: method.result, isStatic: false, isInterface: false, isAbstract: false)
                        b.instructions.append(.foreignCall(target, receiver: receiver, arguments: args + extra, result: result))
                    } else { b.instructions.append(instruction) }
                case let .getField(field, receiver, result):
                    if let info = values[field.owner], field.name == info.field.name, field.type != info.field.type {
                        let raw = try b.value(info.underlying)
                        b.instructions.append(.getField(info.field, receiver, raw))
                        b.instructions.append(.copy(try convert(raw, to: result.type, b: b), result))
                    } else { b.instructions.append(instruction) }
                case let .putField(field, receiver, value):
                    if let info = values[field.owner], field.name == info.field.name, field.type != info.field.type {
                        b.instructions.append(.putField(info.field, receiver, try convert(value, to: info.underlying, b: b)))
                    } else { b.instructions.append(instruction) }
                default: b.instructions.append(instruction)
                }
            }
            f.instructions = b.instructions; f.locals = b.locals; return f
        }
        for i in output.classes.indices {
            guard let info = values[output.classes[i].name] else { continue }
            for p in output.classes[i].properties.indices where output.classes[i].properties[p].name == info.field.name {
                output.classes[i].properties[p].field = info.field
                if info.sourceField.type != info.field.type { output.classes[i].properties[p].genericSignature = valueSignatures[info.name]!.underlying }
            }
        }
        output.functions = try output.functions.map(calls)
        for i in output.classes.indices { output.classes[i].functions = try output.classes[i].functions.map(calls) }
        for functions in [output.functions] + output.classes.map(\.functions) {
            var signatures: Set<String> = []
            guard functions.allSatisfy({ signatures.insert($0.reference.name + $0.reference.descriptor).inserted }) else { throw JVMFrontendError(message: "Clashing JVM signatures after value-class or @JvmName lowering.") }
        }
        output.stdlibRequirements = output.stdlibRequirements.map { row in
            guard let signature = callableSignatures[row.owner + "." + row.name + row.descriptor],
                  let start = signature.firstIndex(of: "(") else { return row }
            return JVMStdlibRequirement(owner: row.owner, name: String(signature[..<start]), descriptor: String(signature[start...]), source: row.source)
        }
        return output
    }
}
