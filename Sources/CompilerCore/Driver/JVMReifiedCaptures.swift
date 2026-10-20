extension JVMFunctionBuilder {
    struct ReifiedRuntimeToken {
        static let captureWidth = 3
        let klass: JVMValue
        let nullable: JVMValue
        let mutableKind: JVMValue
    }

    static let reifiedMutableCollections: [(kind: String, owner: String)] = [
        ("MutableIterable", "java/lang/Iterable"), ("MutableIterator", "java/util/Iterator"),
        ("MutableCollection", "java/util/Collection"), ("MutableList", "java/util/List"),
        ("MutableSet", "java/util/Set"), ("MutableMap", "java/util/Map"),
    ]

    func reifiedCaptureTypes(_ body: ExprID, specialize: Bool = true) -> [TypeID] {
        guard let range = arena.exprRange(body) else { return [] }
        var found: [SymbolID: TypeID] = [:]
        func collect(_ type: TypeID) {
            let actual = specialize ? program.specialized(type) : type
            switch program.sema.types.kind(of: actual) {
            case let .typeParam(t) where program.isReifiedParameter(actual):
                // A nested inline member owns its own reified parameters;
                // those are specialized at that member's call, not captured
                // while constructing the enclosing object.
                if let site = program.sema.symbols.symbol(t.symbol)?.declSite,
                   site.start.file == range.start.file, site.start.offset >= range.start.offset, site.end.offset <= range.end.offset { return }
                found[t.symbol] = program.sema.types.withNullability(.nonNull, for: actual)
            case let .classType(t):
                for arg in t.args { switch arg { case let .invariant(t), let .out(t), let .in(t): collect(t); case .star: break } }
            case let .kClassType(t): collect(t.argument)
            case let .functionType(f):
                for t in [f.receiver].compactMap({ $0 }) + f.params + [f.returnType] { collect(t) }
            default: break
            }
        }
        for i in arena.exprs.indices {
            let id = ExprID(rawValue: Int32(i))
            guard let r = arena.exprRange(id), r.start.file == range.start.file, r.start.offset >= range.start.offset, r.end.offset <= range.end.offset else { continue }
            for type in [program.sema.bindings.exprType(for: id), program.sema.bindings.isCheckTargetType(for: id), program.sema.bindings.castTargetType(for: id), program.sema.bindings.classRefTargetType(for: id)].compactMap({ $0 }) { collect(type) }
            for type in program.sema.bindings.callBinding(for: id)?.substitutedTypeArguments ?? [] { collect(type) }
            for type in program.sema.bindings.callableReferenceBinding(for: id)?.substitutedTypeArguments ?? [] { collect(type) }
        }
        return found.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
    }

    func runtimeReifiedToken(_ semantic: TypeID) throws -> ReifiedRuntimeToken? {
        let actual = program.specialized(semantic)
        switch program.sema.types.kind(of: actual) {
        case let .typeParam(t):
            guard let token = reifiedRuntimeTokens[t.symbol] else { return nil }
            return ReifiedRuntimeToken(klass: token.klass, nullable: try t.nullability == .nullable ? constant(.boolean(true), .boolean) : token.nullable, mutableKind: token.mutableKind)
        case let .classType(t) where (try? program.className(t.classSymbol)) == "kotlin/Array":
            guard let arg = t.args.first else { return nil }
            let element: TypeID
            switch arg { case let .invariant(t), let .out(t): element = t; default: return nil }
            guard let token = try runtimeReifiedToken(element) else { return nil }
            let array = try reflectiveArray(token.klass, count: constant(.int(0), .int))
            let klass = try jdkCall("java/lang/Object", "getClass", [], token.klass.type, receiver: array)!
            // An array's component mutability does not constrain its elements
            // during an erased JVM array check.
            return ReifiedRuntimeToken(klass: klass, nullable: try constant(.boolean(t.nullability == .nullable), .boolean), mutableKind: try constant(.int(0), .int))
        default: return nil
        }
    }

    func materializeReifiedToken(_ semantic: TypeID) throws -> ReifiedRuntimeToken {
        if let token = try runtimeReifiedToken(semantic) { return token }
        guard let name = program.reifiedUse(semantic) else {
            let actual = program.specialized(semantic)
            guard program.validReifiedArgument(actual) else { throw fail("A non-reified type parameter cannot be captured as a reified argument.") }
            let type = try program.classTokenType(actual)
            let klass = try javaClass(type == .unit ? .reference("kotlin/Unit", nullable: false) : JVMClasspathIndex.boxed(type))
            let kind = mutableCollectionKind(actual).flatMap { kind in Self.reifiedMutableCollections.firstIndex { $0.kind == kind } }.map { Int32($0 + 1) } ?? 0
            return ReifiedRuntimeToken(klass: klass, nullable: try constant(.boolean(program.sema.types.nullability(of: actual) == .nullable), .boolean), mutableKind: try constant(.int(kind), .int))
        }
        let klass = try value(.reference("java/lang/Class", nullable: false))
        instructions.append(.reifiedOperation(4, name, nil, klass))
        let null = try constant(.null, .reference("java/lang/Object", nullable: true)), nullable = try value(.boolean)
        instructions.append(.reifiedOperation(3, name, null, nullable))
        return ReifiedRuntimeToken(klass: klass, nullable: nullable, mutableKind: try reifiedMutableKind(klass: klass, name: name))
    }

    /// Class literals erase List and MutableList to the same JDK interface.
    /// A marker check on a standard read-only value lets the foreign Kotlin
    /// inliner preserve that distinction without a repository-specific ABI.
    private func reifiedMutableKind(klass: JVMValue, name: String) throws -> JVMValue {
        let result = try constant(.int(0), .int), probe = try value(.reference("java/lang/Object", nullable: true))
        let inspect = label(), end = label()
        for (index, collection) in Self.reifiedMutableCollections.enumerated() {
            let next = label(), same = try value(.boolean), raw = try javaClass(.reference(collection.owner, nullable: false))
            instructions.append(.referenceCompare(.equal, klass, raw, same)); instructions.append(.jumpIfFalse(same, next))
            let readOnly: JVMValue
            if collection.kind == "MutableMap" {
                readOnly = try jdkCall("kotlin/collections/MapsKt", "emptyMap", [], .reference("java/util/Map", nullable: false))!
            } else if collection.kind == "MutableSet" {
                readOnly = try jdkCall("kotlin/collections/SetsKt", "emptySet", [], .reference("java/util/Set", nullable: false))!
            } else {
                let list = try jdkCall("kotlin/collections/CollectionsKt", "emptyList", [], .reference("java/util/List", nullable: false))!
                readOnly = collection.kind == "MutableIterator"
                    ? try jdkCall("java/lang/Iterable", "iterator", [], .reference("java/util/Iterator", nullable: false), receiver: list, interface: true)!
                    : list
            }
            instructions.append(.constant(.int(Int32(index + 1)), result))
            instructions.append(.copy(readOnly, probe)); jump(inspect)
            mark(next)
        }
        jump(end); mark(inspect)
        let acceptsReadOnly = try value(.boolean)
        instructions.append(.reifiedOperation(3, name, probe, acceptsReadOnly))
        instructions.append(.jumpIfFalse(acceptsReadOnly, end)); instructions.append(.constant(.int(0), result))
        mark(end); return result
    }

    func reflectiveArray(_ klass: JVMValue, count: JVMValue) throws -> JVMValue {
        try jdkCall("java/lang/reflect/Array", "newInstance", [klass.type, .int], .reference("java/lang/Object", nullable: false), arguments: [klass, count])!
    }

    func runtimeInstanceCheck(_ object: JVMValue, token: ReifiedRuntimeToken) throws -> JVMValue {
        let result = try jdkCall("java/lang/Class", "isInstance", [object.type], .boolean, receiver: token.klass, arguments: [object])!
        let checked = label()
        for (index, collection) in Self.reifiedMutableCollections.enumerated() {
            let next = label(), selected = try value(.boolean), kind = try constant(.int(Int32(index + 1)), .int)
            instructions.append(.binary(.equal, token.mutableKind, kind, selected)); instructions.append(.jumpIfFalse(selected, next))
            instructions.append(.copy(try mutableCollectionCheck(object, kind: collection.kind), result)); jump(checked)
            mark(next)
        }
        mark(checked)
        let nonnull = label(), end = label(), null = try constant(.null, .reference("java/lang/Object", nullable: true)), check = try value(.boolean)
        instructions.append(.referenceCompare(.notEqual, object, null, check)); instructions.append(.jumpIfFalse(check, nonnull)); jump(end)
        mark(nonnull); instructions.append(.copy(token.nullable, result)); mark(end)
        return result
    }

    func runtimeCast(_ object: JVMValue, token: ReifiedRuntimeToken, safe: Bool, type: JVMValueType) throws -> JVMValue {
        let check = try runtimeInstanceCheck(object, token: token), rejected = label(), end = label(), result = try value(type)
        instructions.append(.jumpIfFalse(check, rejected))
        instructions.append(.copy(try convert(object, to: type), result)); jump(end)
        mark(rejected)
        if safe { instructions.append(.constant(.null, result)) }
        else {
            let notNull = label(), null = try constant(.null, .reference("java/lang/Object", nullable: true)), isNull = try value(.boolean)
            instructions.append(.referenceCompare(.equal, object, null, isNull)); instructions.append(.jumpIfFalse(isNull, notNull))
            let nullError = try constructJDK("java/lang/NullPointerException")
            instructions.append(.throwValue(nullError)); terminated = true; mark(notNull)
            let error = try constructJDK("java/lang/ClassCastException")
            instructions.append(.throwValue(error)); terminated = true
        }
        mark(end); return result
    }
}
