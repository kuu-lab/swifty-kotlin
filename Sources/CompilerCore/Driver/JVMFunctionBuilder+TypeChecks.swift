extension JVMFunctionBuilder {
    func checkedCast(_ source: ExprID, safe: Bool, id: ExprID) throws -> JVMValue {
        let raw = try requireValue(source)
        let object = try convert(raw, to: .reference("java/lang/Object", nullable: true))
        let type = try program.expressionType(id)
        if let semantic = program.sema.bindings.castTargetType(for: id), let token = try runtimeReifiedToken(semantic) {
            return try runtimeCast(object, token: token, safe: safe, type: type)
        }
        if let semantic = program.sema.bindings.castTargetType(for: id), let name = program.reifiedUse(semantic) {
            let result = try value(type)
            instructions.append(.reifiedOperation(safe ? 2 : 1, name, object, result))
            return result
        }
        if let semantic = program.sema.bindings.castTargetType(for: id), let collection = mutableCollectionKind(semantic) {
            if !safe {
                if type.isNullable {
                    let result = try value(type), nonNull = label(), end = label()
                    let null = try constant(.null, object.type), check = try value(.boolean)
                    instructions.append(.referenceCompare(.equal, object, null, check))
                    instructions.append(.jumpIfFalse(check, nonNull))
                    instructions.append(.constant(.null, result)); jump(end)
                    mark(nonNull)
                    let checked = try jdkCall("kotlin/jvm/internal/TypeIntrinsics", "as" + collection, [object.type], type, arguments: [object])!
                    instructions.append(.copy(checked, result)); mark(end)
                    return result
                }
                // The shared ABI helper accepts null for official nullable
                // casts; a non-null Kotlin target checks it at this call site.
                _ = try jdkCall("java/util/Objects", "requireNonNull", [object.type], object.type, arguments: [object])
                return try jdkCall("kotlin/jvm/internal/TypeIntrinsics", "as" + collection, [object.type], type, arguments: [object])!
            }
            let result = try value(type), no = label(), end = label()
            let check = try mutableCollectionCheck(object, kind: collection)
            instructions.append(.jumpIfFalse(check, no))
            instructions.append(.copy(try convert(object, to: type), result)); jump(end)
            mark(no); instructions.append(.constant(.null, result)); mark(end)
            return result
        }
        if !safe {
            // `as` against a null value throws an NPE naming the Kotlin target
            // type; the shared conversion's bare requireNonNull lacks it.
            if !type.isNullable, object.type.isNullable, let semantic = program.sema.bindings.castTargetType(for: id) {
                let nonNull = label(), result = try value(type)
                let null = try constant(.null, object.type), check = try value(.boolean)
                instructions.append(.referenceCompare(.equal, object, null, check))
                instructions.append(.jumpIfFalse(check, nonNull))
                let message = try constant(.string("null cannot be cast to non-null type " + castTargetKotlinName(semantic)), .string)
                instructions.append(.throwValue(try constructJDK("java/lang/NullPointerException", parameters: [.string], arguments: [message])))
                terminated = true
                mark(nonNull)
                instructions.append(.copy(try convert(object, to: type), result))
                return result
            }
            return try convert(object, to: type)
        }
        let target = JVMClasspathIndex.boxed(type)
        guard let name = target.referenceName else { throw fail("Unsupported JVM safe cast.", id) }
        let result = try value(type), check = try value(.boolean), no = label(), end = label()
        instructions.append(.instanceOf(object, name, check)); instructions.append(.jumpIfFalse(check, no))
        instructions.append(.copy(try convert(object, to: type), result)); jump(end)
        mark(no); instructions.append(.constant(.null, result)); mark(end)
        return result
    }
    func instanceCheck(_ source: ExprID, target: TypeRefID, negated: Bool, id: ExprID) throws -> JVMValue {
        guard let semantic = program.sema.bindings.isCheckTargetType(for: id) else { throw fail("Missing JVM runtime type check.", id) }
        return try instanceCheckValue(requireValue(source), semantic: semantic, negated: negated, id: id)
    }
    func instanceCheckValue(_ raw: JVMValue, semantic: TypeID, negated: Bool, id: ExprID) throws -> JVMValue {
        let actual = program.specialized(semantic)
        if let token = try runtimeReifiedToken(semantic) {
            let result = try runtimeInstanceCheck(convert(raw, to: .reference("java/lang/Object", nullable: true)), token: token)
            if negated { instructions.append(.unary(.not, result, result)) }
            return result
        }
        if let name = program.reifiedUse(semantic) {
            let object = try convert(raw, to: .reference("java/lang/Object", nullable: true)), result = try value(.boolean)
            instructions.append(.reifiedOperation(3, name, object, result))
            if negated { instructions.append(.unary(.not, result, result)) }
            return result
        }
        let type = JVMClasspathIndex.boxed(try program.type(actual))
        guard let name = type.referenceName else { throw fail("Unsupported JVM runtime type check.", id) }
        let object = try convert(raw, to: .reference("java/lang/Object", nullable: true))
        let result = try value(.boolean)
        if let collection = mutableCollectionKind(actual) {
            instructions.append(.copy(try mutableCollectionCheck(object, kind: collection), result))
        } else {
            instructions.append(.instanceOf(object, name, result))
        }
        if program.sema.types.nullability(of: actual) != .nonNull {
            let null = try constant(.null, .reference("java/lang/Object", nullable: true)), check = try value(.boolean)
            let end = label()
            instructions.append(.referenceCompare(.notEqual, object, null, check)); instructions.append(.jumpIfFalse(check, end))
            let done = label(); jump(done)
            mark(end); instructions.append(.constant(.boolean(true), result)); mark(done)
        }
        if negated { instructions.append(.unary(.not, result, result)) }
        return result
    }

    func castTargetKotlinName(_ semantic: TypeID) -> String {
        switch program.sema.types.kind(of: program.specialized(semantic)) {
        case let .classType(type):
            return program.sema.symbols.symbol(type.classSymbol)?.fqName.map(context.interner.resolve).joined(separator: ".") ?? "kotlin.Any"
        case let .primitive(primitive, _): return "kotlin." + primitive.kotlinName
        case .stringStruct: return "kotlin.String"
        case let .typeParam(parameter):
            return program.sema.symbols.symbol(parameter.symbol).map { context.interner.resolve($0.name) } ?? "T"
        case let .functionType(function):
            return "kotlin.Function" + String(function.params.count + (function.receiver == nil ? 0 : 1))
        case .unit: return "kotlin.Unit"
        default: return "kotlin.Any"
        }
    }

    func mutableCollectionKind(_ semantic: TypeID) -> String? {
        // TypeIntrinsics implements these checks using erased JDK interfaces
        // after checking Kotlin's mutability markers; do not call itself.
        guard !(context.options.stdlibOnly && program.facadeName == "kotlin/jvm/internal/TypeIntrinsics"),
              case let .classType(type) = program.sema.types.kind(of: program.specialized(semantic)),
              let symbol = program.sema.symbols.symbol(type.classSymbol) else { return nil }
        let path = symbol.fqName.map(context.interner.resolve)
        guard path.count == 3, Array(path.prefix(2)) == ["kotlin", "collections"],
              ["MutableIterable", "MutableIterator", "MutableCollection", "MutableList", "MutableSet", "MutableMap"].contains(path[2]) else { return nil }
        return path[2]
    }

    func mutableCollectionCheck(_ object: JVMValue, kind: String) throws -> JVMValue {
        try jdkCall("kotlin/jvm/internal/TypeIntrinsics", "is" + kind, [object.type], .boolean, arguments: [object])!
    }
}
