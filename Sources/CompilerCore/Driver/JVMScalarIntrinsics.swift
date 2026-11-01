import Foundation

extension JVMFunctionBuilder {
    static let numericConversions: [String: JVMValueType] = [
        "toByte": .byte, "toShort": .short, "toChar": .char, "toInt": .int,
        "toLong": .long, "toFloat": .float, "toDouble": .double,
        "toUByte": .ubyte, "toUShort": .ushort, "toUInt": .uint, "toULong": .ulong,
    ]

    func charFromCode(_ input: JVMValue) throws -> JVMValue {
        let code = try convert(input, to: .int), check = try value(.boolean), result = try value(.char)
        let invalid = label(), end = label(), minimum = try constant(.int(0), .int), maximum = try constant(.int(65535), .int)
        instructions += [.binary(.greaterOrEqual, code, minimum, check), .jumpIfFalse(check, invalid), .binary(.lessOrEqual, code, maximum, check), .jumpIfFalse(check, invalid), .copy(code, result)]
        jump(end); mark(invalid)
        let prefix = try constant(.string("Invalid Char code: "), .string)
        let number = try jdkCall("java/lang/String", "valueOf", [.int], .string, arguments: [code])!
        let message = try jdkCall("java/lang/String", "concat", [.string], .string, receiver: prefix, arguments: [number])!
        let error = try constructJDK("java/lang/IllegalArgumentException", parameters: [.string], arguments: [message])
        instructions.append(.throwValue(error)); mark(end)
        return result
    }
    func scalarConstant(_ id: ExprID) throws -> JVMValue? {
        guard case let .memberCall(receiver, name, _, args, _) = arena.expr(id), args.isEmpty,
              let symbol = program.sema.bindings.identifierSymbol(for: receiver),
              let declaration = program.sema.symbols.symbol(symbol) else { return nil }
        var path = declaration.fqName.map(context.interner.resolve)
        if path.last == "Companion" { path.removeLast() }
        if path == ["java", "lang", "Math"], declaration.declSite.map({ context.sourceManager.origin(of: $0.start.file) != .user }) == true {
            switch context.interner.resolve(name) {
            case "PI": return try constant(.double(.pi), .double)
            case "E": return try constant(.double(2.718281828459045), .double)
            default: return nil
            }
        }
        guard path.count == 2, path[0] == "kotlin", let primitive = [PrimitiveType.char, .byte, .short, .uint, .ulong, .ubyte, .ushort, .int, .long, .float, .double].first(where: { $0.kotlinName == path[1] }) else { return nil }
        let member = context.interner.resolve(name), type = JVMValueType.primitive(primitive)
        let bits = [.byte, .ubyte].contains(type) ? 8 : ([.char, .short, .ushort].contains(type) ? 16 : (type.width == 2 ? 64 : 32))
        if member == "SIZE_BITS" || member == "SIZE_BYTES" { return try constant(.int(Int32(member == "SIZE_BITS" ? bits : bits / 8)), .int) }
        if type == .float || type == .double {
            let number: Double
            switch member {
            case "NaN": number = .nan
            case "POSITIVE_INFINITY": number = .infinity
            case "NEGATIVE_INFINITY": number = -.infinity
            case "MIN_VALUE": number = type == .float ? Double(Float.leastNonzeroMagnitude) : Double.leastNonzeroMagnitude
            case "MAX_VALUE": number = type == .float ? Double(Float.greatestFiniteMagnitude) : Double.greatestFiniteMagnitude
            default: return nil
            }
            return try constant(type == .float ? .float(Float(number)) : .double(number), type)
        }
        guard member == "MIN_VALUE" || member == "MAX_VALUE" else { return nil }
        let minimum = member == "MIN_VALUE"
        let unsigned = type.unsignedName != nil || type == .char
        let number: Int64
        if unsigned { number = minimum ? 0 : (bits == 64 ? -1 : Int64((UInt64(1) << bits) - 1)) }
        else if bits == 64 { number = minimum ? Int64.min : Int64.max }
        else { number = minimum ? -(Int64(1) << (bits - 1)) : (Int64(1) << (bits - 1)) - 1 }
        if type.width == 2 { return try constant(.long(number), type) }
        // Narrow signed JVM carriers also back UByte and UShort constants.
        let raw = type == .ubyte ? Int32(Int8(truncatingIfNeeded: number)) : (type == .ushort ? Int32(Int16(truncatingIfNeeded: number)) : Int32(truncatingIfNeeded: number))
        return try constant(.int(raw), type)
    }

    func scalarMember(_ receiver: ExprID, name: String, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard let rawType = evaluatedOperands[receiver]?.type ?? (try? program.expressionType(receiver)) else { return nil }
        let sourceType = rawType.numericCarrier ?? rawType
        if let target = Self.numericConversions[name], sourceType.isNumeric, args.isEmpty {
            return JVMIntrinsicResult(value: try convert(requireValue(receiver), to: target))
        }
        if name == "mod", let result = try numericMod(receiver, sourceType: sourceType, args: args, id: id) {
            return JVMIntrinsicResult(value: result)
        }
        if name == "toString", args.count == 1,
           [.byte, .short, .int, .long, .uint, .ulong, .ubyte, .ushort].contains(sourceType)
        {
            let source = try requireValue(receiver)
            let radix = try convert(requireValue(args[0].expr), to: .int)
            let checkedRadix = try jdkCall("kotlin/text/CharsKt", "checkRadix", [.int], .int, arguments: [radix])!
            let owner: String
            let method: String
            let parameters: [JVMValueType]
            let numericValue: JVMValue
            switch sourceType {
            case .long:
                owner = "java/lang/Long"; method = "toString"; parameters = [.long, .int]; numericValue = try convert(source, to: .long)
            case .ulong:
                owner = "java/lang/Long"; method = "toUnsignedString"; parameters = [.long, .int]; numericValue = try convert(source, to: .long)
            case .uint:
                owner = "java/lang/Integer"; method = "toUnsignedString"; parameters = [.int, .int]; numericValue = try convert(source, to: .int)
            case .ubyte, .ushort:
                let mask = sourceType == .ubyte ? 0xff : 0xffff
                let normalized = try value(.int)
                instructions.append(.binary(.bitwiseAnd, try convert(source, to: .int), try constant(.int(Int32(mask)), .int), normalized))
                owner = "java/lang/Integer"; method = "toString"; parameters = [.int, .int]; numericValue = normalized
            default:
                owner = "java/lang/Integer"; method = "toString"; parameters = [.int, .int]; numericValue = try convert(source, to: .int)
            }
            return JVMIntrinsicResult(value: try jdkCall(owner, method, parameters, .string, arguments: [numericValue, checkedRadix]))
        }
        if sourceType == .char, name == "code", args.isEmpty {
            return JVMIntrinsicResult(value: try convert(requireValue(receiver), to: .int))
        }
        if sourceType == .char, name == "plus", args.count == 1, try program.expressionType(id).isText {
            let source = try requireValue(receiver)
            guard let argument = try stringPart(args[0].expr) else { throw JVMTerminatedExpression() }
            return JVMIntrinsicResult(value: try concatenate(source, argument))
        }
        if sourceType.isNumeric || sourceType == .boolean {
            let object: JVMValueType = .reference("java/lang/Object", nullable: true)
            if rawType.isNullable {
                // Nullable receivers reach Any?.hashCode/toString/equals, which
                // are null-safe; the boxed value must not be unboxed here.
                if name == "hashCode", args.isEmpty {
                    let source = try requireValue(receiver)
                    return JVMIntrinsicResult(value: try jdkCall("java/util/Objects", "hashCode", [object], .int, arguments: [source]))
                }
                if name == "toString", args.isEmpty {
                    let source = try requireValue(receiver)
                    return JVMIntrinsicResult(value: try jdkCall("java/util/Objects", "toString", [object], .string, arguments: [source]))
                }
            }
            if name == "equals", args.count == 1 {
                // `x.equals(y)` on a non-null scalar boxes the receiver into its
                // wrapper; nullable receivers reach Any?.equals instead, whose
                // null-safe semantics the same Objects.equals call provides.
                let source = try requireValue(receiver), argument = try requireValue(args[0].expr)
                return JVMIntrinsicResult(value: try jdkCall("java/util/Objects", "equals", [object, object], .boolean, arguments: [source, argument]))
            }
            if name == "toString", args.isEmpty {
                let source = try requireValue(receiver)
                if let owner = sourceType.unsignedName {
                    return JVMIntrinsicResult(value: try jdkCall(owner, "toString-impl", [sourceType], .string, arguments: [source]))
                }
                return JVMIntrinsicResult(value: try jdkCall("java/lang/String", "valueOf", [sourceType.stringParameter], .string, arguments: [source]))
            }
            if name == "hashCode", args.isEmpty {
                let source = try requireValue(receiver)
                return JVMIntrinsicResult(value: try jdkCall(sourceType.boxName!, sourceType.unsignedName == nil ? "hashCode" : "hashCode-impl", [sourceType], .int, arguments: [source]))
            }
            if name == "compareTo", args.count == 1 {
                let source = try requireValue(receiver), argument = try requireValue(args[0].expr)
                let type = try numericType(source.type, argument.type)
                let unsigned = type.unsignedName != nil
                let owner = type.stackType == .long ? "java/lang/Long" : (type == .float ? "java/lang/Float" : (type == .double ? "java/lang/Double" : "java/lang/Integer"))
                let parameter = type.stackType
                return JVMIntrinsicResult(value: try jdkCall(owner, unsigned ? "compareUnsigned" : "compare", [parameter, parameter], .int, arguments: [convert(source, to: type), convert(argument, to: type)]))
            }
            if name == "inv", args.isEmpty {
                let source = try convert(requireValue(receiver), to: sourceType), result = try value(sourceType)
                let bits = try constant(sourceType.width == 2 ? .long(-1) : .int(-1), sourceType)
                instructions.append(.binary(.bitwiseXor, source, bits, result)); return JVMIntrinsicResult(value: result)
            }
            let binaryOps: [String: BinaryOp] = ["plus": .add, "minus": .subtract, "times": .multiply, "div": .divide, "rem": .modulo, "and": .bitwiseAnd, "or": .bitwiseOr, "xor": .bitwiseXor, "shl": .shl, "shr": .shr, "ushr": .ushr]
            if let op = binaryOps[name], args.count == 1 {
                let resultType: JVMValueType
                if case .safeMemberCall = arena.expr(id), let semantic = program.sema.bindings.exprType(for: id) {
                    // Scalar arithmetic runs before the safe-call join boxes
                    // its primitive result into the nullable expression type.
                    resultType = try program.type(program.sema.types.makeNonNullable(semantic))
                } else { resultType = try program.expressionType(id) }
                let result = try value(resultType), source = try convert(requireValue(receiver), to: result.type), argument = try convert(requireValue(args[0].expr), to: [.shl, .shr, .ushr].contains(op) ? .int : result.type)
                instructions.append(.binary(op, source, argument, result)); return JVMIntrinsicResult(value: result)
            }
        }
        return nil
    }
}
