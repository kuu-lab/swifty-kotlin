import Foundation

extension JVMValueType {
    var isCharSequence: Bool { isText || referenceName == "java/lang/StringBuilder" }
    var isText: Bool { referenceName == "java/lang/String" || referenceName == "java/lang/CharSequence" }
}

extension JVMFunctionBuilder {
    func appendText(_ builder: JVMValue, _ input: JVMValue) throws {
        // Arrays must use Object.toString, including CharArray. The char[]
        // overload of append would silently change Kotlin concatenation.
        _ = try jdkCall("java/lang/StringBuilder", "append", [input.type.stringParameter], builder.type, receiver: builder, arguments: [input])
    }
    func concatenate(_ left: JVMValue, _ right: JVMValue) throws -> JVMValue {
        let builder = try constructJDK("java/lang/StringBuilder")
        try appendText(builder, left); try appendText(builder, right)
        return try jdkCall("java/lang/StringBuilder", "toString", [], .string, receiver: builder)!
    }
    /// kotlinc folds a String `+` or template whose operands are all
    /// compile-time constants into one interned literal — `("ab" + "c")
    /// === "abc"` is true because `ldc` observes the shared instance
    /// (KUU-3983). Mirrors the KIR fold in CallLowerer+Operators — same
    /// collector, same `const val`/`literalConstantExpr` operand rules —
    /// so JVM output stays consistent with the native pipeline. A
    /// non-constant operand such as a plain `val`/`var` read leaves nil,
    /// keeping the fresh non-interned StringBuilder result.
    func constantFoldedText(_ id: ExprID) throws -> JVMValue? {
        switch arena.expr(id) {
        case .binary(.add, _, _, _), .memberCall, .stringTemplate:
            break
        default:
            return nil
        }
        guard program.sema.bindings.exprType(for: id) == program.sema.types.stringType,
              ConstantCollector.isBuiltinStringPlusCallee(id, sema: program.sema, interner: context.interner)
        else { return nil }
        var collector = ConstantCollector(floatingPointComparisonSemantics: .ieee754)
        collector.resolvedConstant = { expr in
            ConstantCollector.compileTimeConstantRef(expr, ast: self.program.ast, sema: self.program.sema)
        }
        guard let text = collector.constantStringConcatOperandText(
            id, ast: program.ast, sema: program.sema, interner: context.interner
        ) else { return nil }
        return try constant(.string(text), .string)
    }
    func compoundOperand(_ id: ExprID, target: JVMValueType) throws -> JVMValue {
        if target.isText { return try stringPart(id) ?? value(.string) }
        return try requireValue(id)
    }
    func stringPart(_ id: ExprID) throws -> JVMValue? {
        if let result = try expression(id) { return result }
        if terminated { return nil }
        guard try program.expressionType(id) == .unit else { throw fail("String interpolation requires a value.", id) }
        return try constant(.string("kotlin.Unit"), .string)
    }
    func stringTemplate(_ parts: [StringTemplatePart]) throws -> JVMValue? {
        let builder = try constructJDK("java/lang/StringBuilder")
        for part in parts {
            let input: JVMValue
            switch part {
            case let .literal(s): input = try constant(.string(context.interner.resolve(s)), .string)
            case let .expression(id): guard let result = try stringPart(id) else { return nil }; input = result
            }
            try appendText(builder, input)
        }
        return try jdkCall("java/lang/StringBuilder", "toString", [], .string, receiver: builder)!
    }
    func textLength(_ input: JVMValue) throws -> JVMValue {
        if input.type.referenceName?.hasPrefix("[") == true {
            let result = try value(.int); instructions.append(.arrayLength(input, result)); return result
        }
        let owner = input.type.referenceName == "java/lang/String" ? "java/lang/String" : "java/lang/CharSequence"
        return try jdkCall(owner, "length", [], .int, receiver: convert(input, to: .reference(owner, nullable: false)), interface: owner == "java/lang/CharSequence")!
    }
    func nullableText(_ source: JVMValue, name: String) throws -> JVMValue {
        let result = try value(name == "orEmpty" ? .string : .boolean), nonnull = label(), end = label(), check = try value(.boolean)
        let null = try constant(.null, .reference("java/lang/Object", nullable: true))
        instructions += [.referenceCompare(.equal, source, null, check), .jumpIfFalse(check, nonnull)]
        instructions.append(.constant(name == "orEmpty" ? .string("") : .boolean(true), result)); jump(end); mark(nonnull)
        if name == "orEmpty" { instructions.append(.copy(try convert(source, to: .string), result)) }
        else if name == "isNullOrEmpty" { instructions.append(.binary(.equal, try textLength(source), try constant(.int(0), .int), result)) }
        else { instructions.append(.copy(try jdkCall("kotlin/text/StringsKt", "isBlank", [JVMTextOperation.sequence], .boolean, arguments: [source])!, result)) }
        mark(end); return result
    }

    func implicitTextCall(_ callee: ExprID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard let binding = program.sema.bindings.callBinding(for: id),
              let symbol = program.sema.symbols.symbol(binding.chosenCallee),
              let site = symbol.declSite,
              context.sourceManager.path(of: site.start.file).hasPrefix("<kswiftk-jvm>/text"),
              let semantic = program.sema.symbols.functionSignature(for: binding.chosenCallee)?.receiverType,
              let receiver = implicitExtensionReceiver(id) else { return nil }
        let type = try program.type(semantic)
        guard type.isCharSequence else { return nil }
        return try stringMember(callee, name: context.interner.resolve(symbol.name), args: args, id: id, boundReceiver: convert(receiver, to: type))
    }
    func stringMember(_ receiver: ExprID, name: String, args: [CallArgument], id: ExprID, boundReceiver: JVMValue? = nil) throws -> JVMIntrinsicResult? {
        guard let type = boundReceiver?.type ?? (try? program.expressionType(receiver)) else { return nil }
        func loadReceiver() throws -> JVMValue { try boundReceiver ?? requireValue(receiver) }
        if name == "toString", args.isEmpty, type.referenceName != nil {
            return JVMIntrinsicResult(value: try jdkCall("java/lang/String", "valueOf", [.reference("java/lang/Object", nullable: true)], .string, arguments: [loadReceiver()]))
        }
        guard type.isCharSequence || type.referenceName == "[C" else { return nil }
        if ["length", "lastIndex"].contains(name), args.isEmpty, type.isCharSequence {
            let size = try textLength(loadReceiver())
            if name == "length" { return JVMIntrinsicResult(value: size) }
            let result = try value(.int); instructions.append(.binary(.subtract, size, try constant(.int(1), .int), result)); return JVMIntrinsicResult(value: result)
        }
        if ["orEmpty", "isNullOrEmpty", "isNullOrBlank"].contains(name), args.isEmpty, type.isCharSequence { return JVMIntrinsicResult(value: try nullableText(loadReceiver(), name: name)) }
        if name == "plus", type.isText, args.count == 1 {
            let source = try loadReceiver()
            guard let right = try stringPart(args[0].expr) else { return JVMIntrinsicResult(value: nil) }
            return JVMIntrinsicResult(value: try concatenate(source, right))
        }
        let binding = program.sema.bindings.callBinding(for: id)
        let signature = binding.flatMap { program.sema.symbols.functionSignature(for: $0.chosenCallee) }
        let signatureTypes = try signature?.parameterTypes.map(program.type)
        let candidates = JVMTextOperation.operations.filter { op in
            guard op.name == name else { return false }
            if op.receiver == "CharArray" { return type.referenceName == "[C" }
            return type.isCharSequence && (type.referenceName == "java/lang/String" || op.receiver == "CharSequence")
        }
        let operation = candidates.first { op in
            guard let signatureTypes else { return op.parameters.count == args.count && !op.parameters.contains(where: \.variadic) }
            guard signatureTypes.count == op.parameters.count else { return false }
            return zip(signatureTypes, op.parameters).allSatisfy { actual, parameter in
                actual.descriptor == parameter.type.descriptor || parameter.variadic && actual.descriptor == "[" + parameter.type.descriptor
            }
        } ?? candidates.first { op in
            var supplied: Set<Int> = []
            for (i, arg) in args.enumerated() {
                let index = arg.label.flatMap { label in op.parameters.firstIndex { $0.name == context.interner.resolve(label) } } ?? op.parameters.firstIndex(where: \.variadic) ?? i
                guard op.parameters.indices.contains(index), let actual = try? program.expressionType(arg.expr) else { return false }
                let p = op.parameters[index]
                let expected = p.variadic && arg.isSpread ? "[" + p.type.descriptor : p.type.descriptor
                guard actual.descriptor == expected || actual.isText && p.type.isText else { return false }
                supplied.insert(index)
            }
            return op.parameters.enumerated().allSatisfy { supplied.contains($0.offset) || $0.element.fallback != nil || $0.element.variadic }
        }
        guard let op = operation else {
            guard !candidates.isEmpty else { return nil }
            throw fail("Unsupported JVM text overload: " + name + " (" + (signatureTypes?.map(\.descriptor).joined() ?? "unresolved") + ").", id)
        }
        let source = try loadReceiver()
        let values = try textArguments(op, args: args, binding: binding, source: source, id: id)
        if ["isEmpty", "isNotEmpty"].contains(name) {
            let result = try value(.boolean); instructions.append(.binary(name == "isEmpty" ? .equal : .notEqual, try textLength(source), try constant(.int(0), .int), result)); return JVMIntrinsicResult(value: result)
        }
        if name == "isNotBlank" {
            let result = try jdkCall(op.owner, "isBlank", [op.receiverType], .boolean, arguments: [source])!
            instructions.append(.unary(.not, result, result)); return JVMIntrinsicResult(value: result)
        }
        if name == "uppercase" || name == "lowercase" {
            let locale = try value(.reference("java/util/Locale", nullable: false))
            instructions.append(.getStatic(JVMField(owner: "java/util/Locale", name: "ROOT", type: locale.type, access: 0x19), locale))
            return JVMIntrinsicResult(value: try jdkCall("java/lang/String", name == "uppercase" ? "toUpperCase" : "toLowerCase", [locale.type], .string, receiver: source, arguments: [locale]))
        }
        if name == "reversed" {
            let builder = try constructJDK("java/lang/StringBuilder", parameters: [.string], arguments: [source])
            _ = try jdkCall("java/lang/StringBuilder", "reverse", [], builder.type, receiver: builder)
            return JVMIntrinsicResult(value: try jdkCall("java/lang/StringBuilder", "toString", [], .string, receiver: builder))
        }
        var parameters = op.parameters.map { $0.variadic ? JVMValueType.reference("[" + $0.type.descriptor, nullable: false) : $0.type }
        var arguments = values
        if op.owner.hasPrefix("java/lang/"), op.method?.hasPrefix("parse") == true, parameters.count == 1 {
            arguments[0] = try jdkCall("kotlin/text/CharsKt", "checkRadix", [.int], .int, arguments: [arguments[0]])!
        }
        let result: JVMValue
        if op.instance {
            result = try jdkCall(op.owner, op.method ?? name, parameters, op.result, receiver: convert(source, to: op.receiverType), arguments: arguments, interface: op.owner == "java/lang/CharSequence")!
        } else {
            parameters.insert(op.receiverType, at: 0); arguments.insert(source, at: 0)
            result = try jdkCall(op.owner, op.method ?? name, parameters, op.result, arguments: arguments)!
        }
        if op.sourceResult == "String", result.type != .string {
            return JVMIntrinsicResult(value: try jdkCall("java/lang/Object", "toString", [], .string, receiver: result))
        }
        return JVMIntrinsicResult(value: result)
    }

    func textArguments(_ op: JVMTextOperation, args: [CallArgument], binding: CallBinding?, source: JVMValue, id: ExprID) throws -> [JVMValue] {
        var supplied: [Int: JVMValue] = [:], variadic: [(JVMValue, Bool)] = []
        let varargIndex = op.parameters.firstIndex(where: \.variadic)
        let mapping = args.enumerated().map { i, arg in
            binding?.parameterMapping[i] ?? arg.label.flatMap { label in op.parameters.firstIndex { $0.name == context.interner.resolve(label) } } ?? (varargIndex ?? i)
        }
        let lastVararg = varargIndex.flatMap { mapping.lastIndex(of: $0) }
        for (i, arg) in args.enumerated() {
            let index = mapping[i]
            guard op.parameters.indices.contains(index) else { throw fail("Invalid JVM text argument.", id) }
            let input = try requireValue(arg.expr)
            if index == varargIndex {
                let parameter = op.parameters[index]
                let spread = arg.isSpread || arg.label != nil && input.type.referenceName?.hasPrefix("[") == true
                // Reference spreads snapshot each argument immediately. Primitive
                // spreads retain their arrays until the whole vararg is assembled,
                // matching Kotlin's SpreadBuilder and CharSpreadBuilder respectively.
                if spread && parameter.type.referenceName != nil {
                    let array = JVMValueType.reference("[" + parameter.type.descriptor, nullable: false)
                    let erased = JVMValueType.reference("[Ljava/lang/Object;", nullable: false)
                    let snapshot = try jdkCall("java/util/Arrays", "copyOf", [erased, .int], erased, arguments: [input, textLength(input)], resolved: array)!
                    variadic.append((snapshot, true))
                } else { variadic.append((input, spread)) }
                // Later named arguments must observe the completed copy, even
                // for a single primitive spread or a named array argument.
                if i == lastVararg { supplied[index] = try textVararg(variadic, element: parameter.type) }
            } else {
                guard !arg.isSpread, supplied[index] == nil else { throw fail("Duplicate JVM text argument.", id) }
                supplied[index] = input
            }
        }
        var values: [JVMValue] = []
        for (index, p) in op.parameters.enumerated() {
            if p.variadic { values.append(try supplied[index] ?? textVararg([], element: p.type)); continue }
            if let input = supplied[index] { values.append(try convert(input, to: p.type)); continue }
            let fallback: JVMValue
            switch p.fallback {
            case "false": fallback = try constant(.boolean(false), .boolean)
            case "0": fallback = try constant(.int(0), .int)
            case "10": fallback = try constant(.int(10), .int)
            case "space": fallback = try constant(.int(32), .char)
            case "margin": fallback = try constant(.string("|"), .string)
            case "this": fallback = source
            case "length": fallback = try textLength(source)
            case "lastIndex":
                fallback = try value(.int); instructions.append(.binary(.subtract, try textLength(source), try constant(.int(1), .int), fallback))
            default: throw fail("Missing required JVM text argument.", id)
            }
            values.append(fallback)
        }
        return values
    }
    func textVararg(_ inputs: [(JVMValue, Bool)], element: JVMValueType) throws -> JVMValue {
        let count = try value(.int), one = try constant(.int(1), .int)
        instructions.append(.constant(.int(0), count))
        for (input, spread) in inputs {
            let size = spread ? try textLength(input) : one
            instructions.append(.binary(.add, count, size, count))
        }
        let array = try value(.reference("[" + element.descriptor, nullable: false)), offset = try value(.int)
        instructions += [.newArray(element, count: count, result: array), .constant(.int(0), offset)]
        for (input, spread) in inputs {
            if !spread { instructions += [.arraySet(array, offset, try convert(input, to: element)), .binary(.add, offset, one, offset)]; continue }
            let size = try textLength(input), index = try value(.int), check = try value(.boolean), loop = label(), end = label(), item = try value(element)
            instructions.append(.constant(.int(0), index)); mark(loop)
            instructions += [.binary(.lessThan, index, size, check), .jumpIfFalse(check, end), .arrayGet(input, index, item), .arraySet(array, offset, item), .binary(.add, offset, one, offset), .binary(.add, index, one, index)]
            jump(loop); mark(end)
        }
        return array
    }
}
