import Foundation
import CompilerCore

struct JVMMethodCode {
    let name: UInt16
    let descriptor: UInt16
    let access: UInt16
    let code: Data
    let stack: UInt16
    let locals: UInt16
    let frames: Data?
    var exceptions: [(UInt16, UInt16, UInt16, UInt16)] = []
    var signature: String? = nil
    var annotations: [JVMAnnotation] = []
    var parameterAnnotations: [[JVMAnnotation]] = []
    var annotationDefault: JVMAnnotationValue? = nil
    var isDeprecated = false
}

final class JVMMethodEmitter {
    let function: JVMFunction
    let owner: String
    let pool: JVMConstantPool
    var assembler = JVMAssembler()
    var handlerStacks: [Int: String] = [:]
    var handlerOffsets: Set<Int> = []
    var preservedHandlerSlots: [Int: Set<Int>] = [:]
    var allocationOffsets: [Int: Int] = [:]
    var maxStack = 4
    var uninitialized: [Int: Int] = [:]
    var frameUninitialized: [Int: [Int: Int]] = [:]
    var inlineAllocations: [Int: String] = [:]

    init(function: JVMFunction, owner: String, pool: JVMConstantPool) {
        self.function = function; self.owner = owner; self.pool = pool
    }
    func local(_ opcode: UInt8, _ slot: Int) {
        if slot > 255 { assembler.code.u1(0xC4); assembler.code.u1(opcode); assembler.code.u2(UInt16(slot)) }
        else { assembler.code.u1(opcode); assembler.code.u1(UInt8(slot)) }
    }
    func load(_ value: JVMValue) {
        let opcode: UInt8
        switch value.type.stackType {
        case .int, .boolean, .byte, .short, .char, .uint, .ulong, .ubyte, .ushort: opcode = 0x15
        case .long: opcode = 0x16
        case .float: opcode = 0x17
        case .double: opcode = 0x18
        case .string, .reference, .unsignedArray: opcode = 0x19
        case .unit: return
        }
        local(opcode, value.slot)
    }
    func store(_ value: JVMValue) {
        let opcode: UInt8
        switch value.type.stackType {
        case .int, .boolean, .byte, .short, .char, .uint, .ulong, .ubyte, .ushort: opcode = 0x36
        case .long: opcode = 0x37
        case .float: opcode = 0x38
        case .double: opcode = 0x39
        case .string, .reference, .unsignedArray: opcode = 0x3A
        case .unit: return
        }
        local(opcode, value.slot)
    }
    func invoke(_ owner: String, _ name: String, _ descriptor: String, staticBody: Bool = true) throws {
        assembler.code.u1(staticBody ? 0xB8 : 0xB6)
        assembler.code.u2(try pool.member(10, owner: owner, name: name, descriptor: descriptor))
    }
    func mask(_ bits: Int32) throws {
        assembler.code.u1(0x13); assembler.code.u2(try pool.constant(.int(bits))); assembler.code.u1(0x7E)
    }
    func narrow(_ type: JVMValueType) {
        if [.byte, .ubyte].contains(type) { assembler.code.u1(0x91) }
        else if [.short, .ushort].contains(type) { assembler.code.u1(0x93) }
        else if type == .char { assembler.code.u1(0x92) }
    }
    func conversion(_ from: JVMValueType, _ to: JVMValueType) throws {
        if from == to { return }
        let sourceArray: Bool = { if case .unsignedArray = from { return true }; return false }()
        let targetArray: Bool = { if case .unsignedArray = to { return true }; return false }()
        if let target = to.referenceName, !targetArray {
            if let name = from.boxName {
                if sourceArray && target.hasPrefix("[") { return }
                try invoke(name, from.unsignedName == nil ? "valueOf" : "box-impl", "(" + from.descriptor + ")L" + name + ";")
                if target != "java/lang/Object" && target != name { assembler.code.u1(0xC0); assembler.code.u2(try pool.classInfo(target)) }
                return
            }
            if !to.isNullable && from.isNullable {
                try invoke("java/util/Objects", "requireNonNull", "(Ljava/lang/Object;)Ljava/lang/Object;")
            }
            if target != "java/lang/Object" { assembler.code.u1(0xC0); assembler.code.u2(try pool.classInfo(target)) }
            return
        }
        if from.referenceName != nil && !sourceArray {
            if targetArray && from.referenceName?.hasPrefix("[") == true {
                assembler.code.u1(0xC0); assembler.code.u2(try pool.classInfo(to.descriptor)); return
            }
            guard let name = to.boxName else { throw JVMEmissionError.limit("Unsupported JVM unboxing conversion.") }
            let method: String
            if to.unsignedName != nil { method = "unbox-impl" }
            else { method = to == .char ? "charValue" : (to == .int ? "intValue" : String(name.split(separator: "/").last!).lowercased() + "Value") }
            assembler.code.u1(0xC0); assembler.code.u2(try pool.classInfo(name))
            try invoke(name, method, "()" + to.descriptor, staticBody: false)
            return
        }
        if sourceArray || targetArray {
            if !to.isNullable && from.isNullable { try invoke("java/util/Objects", "requireNonNull", "(Ljava/lang/Object;)Ljava/lang/Object;"); assembler.code.u1(0xC0); assembler.code.u2(try pool.classInfo(to.descriptor)) }
            return
        }
        // UByte/UShort use signed JVM storage; zero-extend before arithmetic
        // or widening, but retain signed bits at their B/S ABI boundary.
        if from == .ubyte { try mask(255) }
        if from == .ushort { try mask(65535) }
        let f = from.stackType, t = to.stackType
        if [.float, .double].contains(t), [.uint, .ulong].contains(from) {
            try invoke("kotlin/UnsignedKt", from == .uint ? "uintToDouble" : "ulongToDouble", "(" + from.descriptor + ")D")
            if t == .float { assembler.code.u1(0x90) }
        } else if [.float, .double].contains(f), [.uint, .ulong].contains(to) {
            if f == .float { assembler.code.u1(0x8D) }
            try invoke("kotlin/UnsignedKt", to == .uint ? "doubleToUInt" : "doubleToULong", "(D)" + to.descriptor)
        } else if f != t {
            let opcodes: [JVMValueType: [JVMValueType: UInt8]] = [
                .int: [.long: 0x85, .float: 0x86, .double: 0x87],
                .long: [.int: 0x88, .float: 0x89, .double: 0x8A],
                .float: [.int: 0x8B, .long: 0x8C, .double: 0x8D],
                .double: [.int: 0x8E, .long: 0x8F, .float: 0x90],
            ]
            guard let opcode = opcodes[f]?[t] else { throw JVMEmissionError.limit("Unsupported JVM numeric conversion.") }
            assembler.code.u1(opcode)
            if from == .uint && t == .long {
                assembler.code.u1(0x14); assembler.code.u2(try pool.constant(.long(4294967295))); assembler.code.u1(0x7F)
            }
        }
        narrow(to)
    }
    func emit() throws -> JVMMethodCode {
        if function.isAbstract {
            return JVMMethodCode(name: try pool.utf8(function.reference.name), descriptor: try pool.utf8(function.reference.descriptor), access: (function.access ?? 0x0401) | (function.isHiddenByDeprecation ? 0x1000 : 0), code: Data(), stack: 0, locals: 0, frames: nil, exceptions: [], signature: function.genericSignature)
        }
        if function.isConstructor { uninitialized[0] = -1 }
        // Fixed-type, eagerly initialized scratch locals keep all CFG joins
        // verifier-compatible. Source definite-assignment checks happen in Sema.
        for parameter in function.locals.prefix(function.parameterCount) where function.checksParameters && parameter.type.referenceName != nil && !parameter.type.isNullable && (function.owner == nil || parameter.slot != 0 || function.access == nil) {
            load(parameter)
            if function.isInline {
                // Kotlin's bytecode inliner removes this recognized check when
                // replacing a function parameter with the caller's lambda body.
                assembler.code.u1(0x13)
                assembler.code.u2(try pool.constant(.string("parameter")))
                assembler.code.u1(0xB8)
                assembler.code.u2(try pool.member(10, owner: "kotlin/jvm/internal/Intrinsics", name: "checkNotNullParameter", descriptor: "(Ljava/lang/Object;Ljava/lang/String;)V"))
            } else {
                assembler.code.u1(0xB8)
                assembler.code.u2(try pool.member(10, owner: "java/util/Objects", name: "requireNonNull", descriptor: "(Ljava/lang/Object;)Ljava/lang/Object;"))
                assembler.code.u1(0x57)
            }
        }
        for value in function.locals.dropFirst(function.parameterCount) {
            let opcode: UInt8
            switch value.type.stackType {
            case .long: opcode = 0x09
            case .float: opcode = 0x0B
            case .double: opcode = 0x0E
            case .string, .reference, .unsignedArray: opcode = 0x01
            default: opcode = 0x03
            }
            assembler.code.u1(opcode); store(value)
        }
        for instruction in function.instructions {
            try emit(instruction)
            for offset in assembler.frames where frameUninitialized[offset] == nil { frameUninitialized[offset] = uninitialized }
        }
        let code = try assembler.finish()
        let frames = try stackMaps(codeSize: code.count)
        return JVMMethodCode(
            name: try pool.utf8(function.reference.name), descriptor: try pool.utf8(function.reference.descriptor),
            access: (function.access ?? (function.isPrivate ? 0x000A : 0x0009)) | (function.typeParameters.contains(where: \.isReified) || function.isHiddenByDeprecation ? 0x1000 : 0), code: code, stack: UInt16(maxStack),
            locals: UInt16(function.locals.last.map { $0.slot + $0.type.width } ?? 0), frames: frames,
            exceptions: try function.handlers.compactMap { h in
                guard let start = assembler.labels[h.start], let end = assembler.labels[h.end], let handler = assembler.labels[h.handler], start <= end else { throw JVMEmissionError.limit("Invalid JVM exception range.") }
                if start == end { return nil }
                return (UInt16(start), UInt16(end), UInt16(handler), try h.type.map(pool.classInfo) ?? 0)
            }, signature: function.genericSignature
        )
    }
    func inlineSuspendResult(key: String, physicalKey: String, result: JVMValue) throws {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        guard let representation = function.inlineSuspendValueResults[key] ?? function.inlineSuspendValueResults[physicalKey] else { try conversion(object, result.type); return }
        let name = representation.boxed.referenceName!
        // Kotlin keeps this conversion on the resumed (boxed) path only.
        // The initial call already returns the raw reference storage.
        try inlineSuspendMarker(8)
        if representation.boxed.isNullable {
            assembler.code.u1(0xB8); assembler.code.u2(try pool.member(10, owner: representation.adapterOwner ?? name, name: "$unboxSuspend$inline", descriptor: "(Ljava/lang/Object;)Ljava/lang/Object;"))
        } else {
            try conversion(object, representation.boxed)
            assembler.code.u1(0xB6); assembler.code.u2(try pool.member(10, owner: name, name: "unbox-impl", descriptor: "()" + representation.underlying.descriptor))
            try conversion(representation.underlying, object)
        }
        // The coroutine transformer consumes this exact trailing CHECKCAST
        // together with marker 9. Keep it even though the JVM cast is redundant.
        assembler.code.u1(0xC0); assembler.code.u2(try pool.classInfo("java/lang/Object"))
        try inlineSuspendMarker(9)
        if representation.boxed.isNullable {
            assembler.code.u1(0xB8); assembler.code.u2(try pool.member(10, owner: representation.adapterOwner ?? name, name: "$boxSuspend$inline", descriptor: "(Ljava/lang/Object;)L" + name + ";"))
        } else {
            try conversion(object, representation.underlying)
            assembler.code.u1(0xB8); assembler.code.u2(try pool.member(10, owner: name, name: "box-impl", descriptor: "(" + representation.underlying.descriptor + ")L" + name + ";"))
        }
        try conversion(representation.boxed, result.type)
    }
    func inlineSuspendMarker(_ id: Int32) throws {
        assembler.code.u1(0x13); assembler.code.u2(try pool.constant(.int(id)))
        assembler.code.u1(0xB8); assembler.code.u2(try pool.member(10, owner: "kotlin/jvm/internal/InlineMarker", name: "mark", descriptor: "(I)V"))
    }
    func emit(_ instruction: JVMInstruction) throws {
        switch instruction {
        case let .inlineFinallyMarker(depth, start):
            assembler.code.u1(0x13); assembler.code.u2(try pool.constant(.int(Int32(depth))))
            assembler.code.u1(0xB8)
            assembler.code.u2(try pool.member(10, owner: "kotlin/jvm/internal/InlineMarker", name: start ? "finallyStart" : "finallyEnd", descriptor: "(I)V"))
        case let .reifiedOperation(op, name, input, result):
            if let input { load(input) }
            assembler.code.u1(0x13); assembler.code.u2(try pool.constant(.int(Int32(op))))
            assembler.code.u1(0x13); assembler.code.u2(try pool.constant(.string(name)))
            assembler.code.u1(0xB8); assembler.code.u2(try pool.member(10, owner: "kotlin/jvm/internal/Intrinsics", name: "reifiedOperationMarker", descriptor: "(ILjava/lang/String;)V"))
            if op == 4 { assembler.code.u1(0x13); assembler.code.u2(try pool.classInfo("java/lang/Object")) }
            else if op == 0 {
                let descriptor = String((result.type.referenceName ?? "[Ljava/lang/Object;").dropFirst())
                let component = descriptor.hasPrefix("L") ? String(descriptor.dropFirst().dropLast()) : descriptor
                assembler.code.u1(0xBD); assembler.code.u2(try pool.classInfo(component))
            }
            else { assembler.code.u1(op == 3 ? 0xC1 : 0xC0); assembler.code.u2(try pool.classInfo(op == 3 ? "java/lang/Object" : (result.type.referenceName ?? "java/lang/Object"))) }
            store(result)
        case let .classLiteral(name, result):
            let index = try pool.classInfo(name)
            if index <= 255 { assembler.code.u1(0x12); assembler.code.u1(UInt8(index)) }
            else { assembler.code.u1(0x13); assembler.code.u2(index) }
            store(result)
        case .callableSignature: throw JVMEmissionError.limit("Unresolved JVM callable signature.")
        case let .constant(constant, result):
            if case .null = constant { assembler.code.u1(0x01) }
            else if case let .boolean(b) = constant { assembler.code.u1(b ? 0x04 : 0x03) }
            else {
                assembler.code.u1(result.type.width == 2 ? 0x14 : 0x13)
                assembler.code.u2(try pool.constant(constant))
            }
            if case .int = constant { narrow(result.type) }
            store(result)
        case let .copy(source, result): load(source); try conversion(source.type, result.type); store(result)
        case let .unary(op, source, result):
            load(source)
            if op == .not { assembler.code.u1(0x04); assembler.code.u1(0x82) }
            else if op == .unaryMinus {
                let opcode: UInt8 = source.type.stackType == .int ? 0x74 : (source.type.stackType == .long ? 0x75 : (source.type == .float ? 0x76 : 0x77))
                assembler.code.u1(opcode)
            }
            narrow(result.type); store(result)
        case let .binary(op, left, right, result): try binary(op, left, right, result)
        case let .referenceCompare(op, left, right, result):
            load(left); load(right); try comparison(op == .equal ? 0xA5 : 0xA6, result)
        case let .call(ref, arguments, result):
            if let continuation = function.inlineContinuation, ref.isSuspend {
                let target = ref.suspendABI
                let masks = ref.suspendDefaultMasks == 0 ? 0 : ref.suspendDefaultMasks + 1
                let inputs = Array(arguments.dropLast(masks)) + [continuation] + (masks == 0 ? [] : Array(arguments.suffix(masks)))
                maxStack = max(maxStack, inputs.reduce(2) { $0 + $1.type.width })
                for argument in inputs { load(argument) }
                try inlineSuspendMarker(0)
                assembler.code.u1(0xB8); assembler.code.u2(try pool.member(target.ownerIsInterface ? 11 : 10, owner: target.owner ?? owner, name: target.name, descriptor: target.descriptor))
                try inlineSuspendMarker(1)
                if let result { try inlineSuspendResult(key: (ref.owner ?? owner) + "." + ref.name + ref.descriptor, physicalKey: (target.owner ?? owner) + "." + target.name + target.descriptor, result: result); store(result) }
                else { assembler.code.u1(0x57) }
                return
            }
            maxStack = max(maxStack, arguments.reduce(0, { $0 + $1.type.width }))
            for argument in arguments { load(argument) }
            assembler.code.u1(0xB8)
            assembler.code.u2(try pool.member(ref.ownerIsInterface ? 11 : 10, owner: ref.owner ?? owner, name: ref.name, descriptor: ref.descriptor))
            if let result { try conversion(ref.result, result.type); store(result) }
            else if ref.result != .unit { assembler.code.u1(ref.result.width == 2 ? 0x58 : 0x57) }
        case let .invokeDynamic(name, descriptor, captures, samDescriptor, implementation, instantiatedDescriptor, result):
            maxStack = max(maxStack, max(1, captures.reduce(0) { $0 + $1.type.width }))
            for capture in captures { load(capture) }
            let index = try pool.invokeDynamic(
                name: name,
                descriptor: descriptor,
                samDescriptor: samDescriptor,
                implementation: implementation,
                instantiatedDescriptor: instantiatedDescriptor
            )
            assembler.code.u1(0xBA); assembler.code.u2(index); assembler.code.u2(0)
            store(result)
        case let .abandonAllocations(objects):
            // Clear only this escaping edge. The other arm of an if still
            // owns the allocation until its invokespecial initializes it.
            for object in objects { assembler.code.u1(0x01); store(object) }
        case let .allocate(name, object):
            if function.isInline {
                // Exported inline bytecode must use NEW/DUP/ctor, without
                // uninitialized scratch locals. Preserve eager JVM class
                // initialization before evaluating the constructor arguments.
                inlineAllocations[object.slot] = name
                assembler.code.u1(0x13); assembler.code.u2(try pool.constant(.string(name.replacingOccurrences(of: "/", with: "."))))
                assembler.code.u1(0xB8); assembler.code.u2(try pool.member(10, owner: "java/lang/Class", name: "forName", descriptor: "(Ljava/lang/String;)Ljava/lang/Class;"))
                assembler.code.u1(0x57)
                return
            }
            uninitialized[object.slot] = assembler.code.data.count
            allocationOffsets[object.slot] = assembler.code.data.count
            assembler.code.u1(0xBB); assembler.code.u2(try pool.classInfo(name)); store(object)
        case let .foreignCall(method, receiver, arguments, result):
            if let continuation = function.inlineContinuation, method.isSuspend {
                let target = method.suspendABI
                maxStack = max(maxStack, arguments.reduce(receiver == nil ? 3 : 4) { $0 + $1.type.width })
                if let receiver { load(receiver) }
                for argument in arguments { load(argument) }; load(continuation)
                try inlineSuspendMarker(0)
                assembler.code.u1(target.isSpecial ? 0xB7 : (target.isStatic ? 0xB8 : (target.isInterface ? 0xB9 : 0xB6)))
                assembler.code.u2(try pool.member(target.isInterface ? 11 : 10, owner: target.owner, name: target.name, descriptor: target.descriptor))
                if target.isInterface && !target.isStatic && !target.isSpecial { assembler.code.u1(UInt8(target.parameters.reduce(1) { $0 + $1.width })); assembler.code.u1(0) }
                try inlineSuspendMarker(1)
                if let result { try inlineSuspendResult(key: method.owner + "." + method.name + method.descriptor, physicalKey: target.owner + "." + target.name + target.descriptor, result: result); store(result) }
                else { assembler.code.u1(0x57) }
                return
            }
            if function.isInline, method.isConstructor, let receiver, let name = inlineAllocations[receiver.slot] {
                assembler.code.u1(0xBB); assembler.code.u2(try pool.classInfo(name)); assembler.code.u1(0x59)
                for argument in arguments { load(argument) }
                assembler.code.u1(0xB7); assembler.code.u2(try pool.member(10, owner: method.owner, name: method.name, descriptor: method.descriptor))
                store(receiver)
                maxStack = max(maxStack, 2 + arguments.reduce(0, { $0 + $1.type.width }))
                return
            }
            maxStack = max(maxStack, arguments.reduce(method.isStatic ? 0 : 1, { $0 + $1.type.width }))
            if let receiver { load(receiver) }
            for argument in arguments { load(argument) }
            assembler.code.u1(method.isConstructor || method.isSpecial ? 0xB7 : (method.isStatic ? 0xB8 : (method.isInterface ? 0xB9 : 0xB6)))
            assembler.code.u2(try pool.member(method.isInterface ? 11 : 10, owner: method.owner, name: method.name, descriptor: method.descriptor))
            if method.isInterface && !method.isStatic && !method.isSpecial {
                assembler.code.u1(UInt8(arguments.reduce(1, { $0 + $1.type.width }))); assembler.code.u1(0)
            }
            if method.isConstructor, let receiver { uninitialized.removeValue(forKey: receiver.slot) }
            if let result { try conversion(method.result, result.type); store(result) }
            else if !method.isConstructor && method.result != .unit { assembler.code.u1(method.result.width == 2 ? 0x58 : 0x57) }
        case let .getStatic(field, result):
            assembler.code.u1(0xB2); assembler.code.u2(try pool.member(9, owner: field.owner, name: field.name, descriptor: field.type.descriptor)); store(result)
        case let .putStatic(field, source):
            load(source); assembler.code.u1(0xB3); assembler.code.u2(try pool.member(9, owner: field.owner, name: field.name, descriptor: field.type.descriptor))
        case let .getField(field, object, result):
            load(object); assembler.code.u1(0xB4)
            assembler.code.u2(try pool.member(9, owner: field.owner, name: field.name, descriptor: field.type.descriptor)); store(result)
        case let .putField(field, object, source):
            load(object); load(source); assembler.code.u1(0xB5)
            assembler.code.u2(try pool.member(9, owner: field.owner, name: field.name, descriptor: field.type.descriptor))
        case let .newArray(element, count, result):
            load(count)
            let codes: [JVMValueType: UInt8] = [.boolean: 4, .char: 5, .float: 6, .double: 7, .byte: 8, .ubyte: 8, .short: 9, .ushort: 9, .int: 10, .uint: 10, .long: 11, .ulong: 11]
            if let code = codes[element] { assembler.code.u1(0xBC); assembler.code.u1(code) }
            else if let name = element.referenceName { assembler.code.u1(0xBD); assembler.code.u2(try pool.classInfo(name)) }
            else { throw JVMEmissionError.limit("Unsupported JVM array element.") }
            store(result)
        case let .arrayLength(array, result): load(array); assembler.code.u1(0xBE); store(result)
        case let .arrayGet(array, index, result):
            load(array); load(index)
            let element = try arrayElement(array.type)
            assembler.code.u1(arrayOpcode(element, store: false)); try conversion(element, result.type); store(result)
        case let .arraySet(array, index, source):
            load(array); load(index); load(source)
            let element = try arrayElement(array.type)
            try conversion(source.type, element); assembler.code.u1(arrayOpcode(element, store: true))
        case let .instanceOf(source, name, result):
            load(source); assembler.code.u1(0xC1); assembler.code.u2(try pool.classInfo(name)); store(result)
        case let .throwValue(source): load(source); assembler.code.u1(0xBF)
        case let .monitor(source, enter): load(source); assembler.code.u1(enter ? 0xC2 : 0xC3)
        case let .regionBoundary(label): assembler.labels[label] = assembler.code.data.count
        case let .exceptionHandler(label, exception, preserving):
            assembler.mark(label)
            let offset = assembler.code.data.count
            handlerStacks[offset] = exception.type.referenceName!
            handlerOffsets.insert(offset)
            let preservedSlots = Set(preserving.map(\.slot))
            preservedHandlerSlots[offset] = preservedSlots
            uninitialized = allocationOffsets.filter { preservedSlots.contains($0.key) }
            if function.isConstructor && preservedSlots.contains(0) { uninitialized[0] = -1 }
            frameUninitialized[offset] = uninitialized
            store(exception)
            // Allocation temporaries can be uninitialized on exceptional edges.
            // Handler frames merge them as TOP, then restore their fixed types.
            for instruction in function.instructions {
                if case let .allocate(_, object) = instruction, !preservedSlots.contains(object.slot) { assembler.code.u1(0x01); store(object) }
            }
        case let .print(argument, newline):
            assembler.code.u1(0xB2)
            assembler.code.u2(try pool.member(9, owner: "java/lang/System", name: "out", descriptor: "Ljava/io/PrintStream;"))
            // A non-null CharArray binds PrintStream.println(char[]), which
            // prints the characters; the Object overload would print the
            // [C@ identity string instead.
            let parameterType = argument.map { arg in
                arg.type.referenceName == "[C" && !arg.type.isNullable ? arg.type : arg.type.stringParameter
            }
            if let argument, let parameterType { load(argument); try conversion(argument.type, parameterType) }
            assembler.code.u1(0xB6)
            assembler.code.u2(try pool.member(10, owner: "java/io/PrintStream", name: newline ? "println" : "print", descriptor: "(" + (parameterType?.descriptor ?? "") + ")V"))
        case let .label(label): assembler.mark(label)
        case let .jump(label): assembler.jump(label)
        case let .jumpIfFalse(value, label): load(value); try assembler.branch(0x99, to: label)
        case let .defaultArgument(mask, bit, label):
            load(mask); assembler.code.u1(0x13); assembler.code.u2(try pool.constant(.int(bit))); assembler.code.u1(0x7E)
            if function.isInline { assembler.shortBranch(0x99, to: label) }
            else { try assembler.branch(0x99, to: label) }
        case let .returnValue(value):
            if function.inlineContinuation != nil {
                if let value { load(value); try conversion(value.type,  .reference("java/lang/Object", nullable: true)) }
                else { assembler.code.u1(0xB2); assembler.code.u2(try pool.member(9, owner: "kotlin/Unit", name: "INSTANCE", descriptor: "Lkotlin/Unit;")) }
                assembler.code.u1(0xB0)
                return
            }
            if let value {
                load(value)
                let opcode: UInt8
                switch value.type.stackType {
                case .long: opcode = 0xAD
                case .float: opcode = 0xAE
                case .double: opcode = 0xAF
                case .string, .reference, .unsignedArray: opcode = 0xB0
                default: opcode = 0xAC
                }
                assembler.code.u1(opcode)
            } else { assembler.code.u1(0xB1) }
        }
    }
    func binary(_ op: BinaryOp, _ left: JVMValue, _ right: JVMValue, _ result: JVMValue) throws {
        load(left)
        if left.type == .ubyte { try mask(255) }; if left.type == .ushort { try mask(65535) }
        load(right)
        if right.type == .ubyte { try mask(255) }; if right.type == .ushort { try mask(65535) }
        if [.uint, .ulong].contains(left.type), [.divide, .modulo].contains(op) {
            let name = left.type == .uint ? "java/lang/Integer" : "java/lang/Long"
            try invoke(name, op == .divide ? "divideUnsigned" : "remainderUnsigned", "(" + left.type.descriptor + right.type.descriptor + ")" + left.type.descriptor)
            narrow(result.type); store(result); return
        }
        if [.bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr].contains(op) {
            let wide: UInt8 = left.type.stackType == .long ? 1 : 0
            let base: UInt8
            switch op {
            case .bitwiseAnd: base = 0x7E
            case .bitwiseOr: base = 0x80
            case .bitwiseXor: base = 0x82
            case .shl: base = 0x78
            case .shr: base = left.type.unsignedName != nil ? 0x7C : 0x7A
            default: base = 0x7C
            }
            assembler.code.u1(base + wide); narrow(result.type); store(result); return
        }
        if [BinaryOp.add, .subtract, .multiply, .divide, .modulo].contains(op) {
            let base: UInt8
            switch op {
            case .add: base = 0x60
            case .subtract: base = 0x64
            case .multiply: base = 0x68
            case .divide: base = 0x6C
            default: base = 0x70
            }
            let offset: UInt8 = left.type.stackType == .int ? 0 : (left.type.stackType == .long ? 1 : (left.type == .float ? 2 : 3))
            assembler.code.u1(base + offset); narrow(result.type); store(result); return
        }
        if left.type.referenceName != nil {
            assembler.code.u1(0xB8)
            assembler.code.u2(try pool.member(10, owner: "java/util/Objects", name: "equals", descriptor: "(Ljava/lang/Object;Ljava/lang/Object;)Z"))
            if op == .notEqual { assembler.code.u1(0x04); assembler.code.u1(0x82) }
            store(result); return
        }
        let unsigned = left.type == .uint || left.type == .ulong
        if unsigned { try invoke(left.type == .uint ? "java/lang/Integer" : "java/lang/Long", "compareUnsigned", "(" + left.type.descriptor + right.type.descriptor + ")I") }
        let integer = !unsigned && (left.type.stackType == .int || left.type == .boolean)
        if !integer && !unsigned {
            let less = op == .lessThan || op == .lessOrEqual
            assembler.code.u1(left.type.stackType == .long ? 0x94 : (left.type == .float ? (less ? 0x96 : 0x95) : (less ? 0x98 : 0x97)))
        }
        let opcode: UInt8
        switch op {
        case .equal: opcode = integer ? 0x9F : 0x99
        case .notEqual: opcode = integer ? 0xA0 : 0x9A
        case .lessThan: opcode = integer ? 0xA1 : 0x9B
        case .greaterOrEqual: opcode = integer ? 0xA2 : 0x9C
        case .greaterThan: opcode = integer ? 0xA3 : 0x9D
        case .lessOrEqual: opcode = integer ? 0xA4 : 0x9E
        default: throw JVMEmissionError.limit("Unsupported JVM comparison.")
        }
        try comparison(opcode, result)
    }
    func comparison(_ opcode: UInt8, _ result: JVMValue) throws {
        let yes = assembler.freshLabel(), end = assembler.freshLabel()
        try assembler.branch(opcode, to: yes)
        assembler.code.u1(0x03); store(result); assembler.jump(end)
        assembler.mark(yes); assembler.code.u1(0x04); store(result); assembler.mark(end)
    }
    func stackMaps(codeSize: Int) throws -> Data? {
        let offsets = assembler.frames.sorted()
        guard !offsets.isEmpty else { return nil }
        var bytes = JVMBytes(); bytes.u2(UInt16(offsets.count))
        var previous = -1
        for offset in offsets {
            guard offset < codeSize else { throw JVMEmissionError.limit("JVM stack-map frame is outside method code.") }
            bytes.u1(255); bytes.u2(UInt16(offset - previous - 1))
            bytes.u2(UInt16(function.locals.count))
            let allocationSlots = Set(function.instructions.compactMap { instruction -> Int? in if case let .allocate(_, object) = instruction { return object.slot }; return nil })
            for value in function.locals {
                if handlerOffsets.contains(offset), allocationSlots.contains(value.slot), !(preservedHandlerSlots[offset]?.contains(value.slot) ?? false) { bytes.u1(0); continue }
                if let allocation = frameUninitialized[offset]?[value.slot] {
                    if allocation == -1 { bytes.u1(6) }
                    else { bytes.u1(8); bytes.u2(UInt16(allocation)) }
                    continue
                }
                switch value.type.stackType {
                case .int, .boolean, .byte, .short, .char, .uint, .ulong, .ubyte, .ushort: bytes.u1(1)
                case .float: bytes.u1(2)
                case .double: bytes.u1(3)
                case .long: bytes.u1(4)
                case .string, .reference, .unsignedArray: bytes.u1(7); bytes.u2(try pool.classInfo(value.type.referenceName!))
                case .unit: throw JVMEmissionError.limit("Unit has no JVM local slot.")
                }
            }
            if let exception = handlerStacks[offset] { bytes.u2(1); bytes.u1(7); bytes.u2(try pool.classInfo(exception)) }
            else { bytes.u2(0) }
            previous = offset
        }
        return bytes.data
    }
}

extension JVMMethodEmitter {
    func arrayElement(_ type: JVMValueType) throws -> JVMValueType {
        guard let name = type.referenceName, name.hasPrefix("[") else { throw JVMEmissionError.limit("Expected JVM array.") }
        if case let .unsignedArray(p, _) = type { return .primitive(p) }
        let descriptor = String(name.dropFirst())
        switch descriptor {
        case "B": return .byte
        case "S": return .short
        case "C": return .char
        case "I": return .int
        case "J": return .long
        case "F": return .float
        case "D": return .double
        case "Z": return .boolean
        default:
            if descriptor.hasPrefix("[") { return .reference(descriptor, nullable: true) }
            guard descriptor.hasPrefix("L"), descriptor.hasSuffix(";") else { throw JVMEmissionError.limit("Unsupported array descriptor.") }
            return .reference(String(descriptor.dropFirst().dropLast()), nullable: true)
        }
    }
    func arrayOpcode(_ type: JVMValueType, store: Bool) -> UInt8 {
        let load: UInt8 = type == .char ? 0x34 : (type == .short || type == .ushort ? 0x35 : (type == .byte || type == .ubyte ? 0x33 : (type == .int || type == .uint ? 0x2E : (type == .long || type == .ulong ? 0x2F : (type == .float ? 0x30 : (type == .double ? 0x31 : (type == .boolean ? 0x33 : 0x32)))))))
        return load + (store ? 0x21 : 0)
    }
}
