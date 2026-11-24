import Foundation

/// Classpath `inline fun <reified T>` bodies are compiled bytecode: their
/// `reifiedOperationMarker` calls throw unless a compiler resolves them.
/// For each call, the body is copied into a generated class with the markers
/// resolved to the call's concrete type arguments.
struct JVMReifiedHost {
    var name = ""
    var clone: JVMReifiedClone?
    var helpers: [JVMFunction] = []
    var helperNames: [String: String] = [:]
    /// Classes the patches name; non-public ones decide the host's package.
    var referencedClasses: Set<String> = []
}

extension JVMProgramBuilder {
    func reifiedHostClasses() -> [JVMClass] {
        // Type arguments that erase to the same classes produce the same content
        // and therefore the same class.
        var seen: Set<String> = []
        return reifiedHosts.values.sorted { $0.name < $1.name }.filter { seen.insert($0.name).inserted }.map { host in
            var type = rawClass(host.name, access: 0x1031, functions: host.helpers)
            type.reifiedClones = host.clone.map { [$0] } ?? []
            return type
        }
    }

    /// Whether another package can name `className` in a class constant.
    func isPubliclyAccessible(_ className: String) -> Bool {
        var name = className
        while name.hasPrefix("[") { name.removeFirst() }
        if name.hasPrefix("L"), name.hasSuffix(";") { name = String(name.dropFirst().dropLast()) }
        if let plan = classes.values.first(where: { $0.name == name }) {
            return !plan.modifiers.contains(.private) || plan.escapesInline
        }
        if let imported = context.jvmImports?.classes[name] { return imported.flags & 1 != 0 }
        return true
    }
}

/// A reified body this compiler cannot clone. The call keeps its direct call
/// (as before cloning existed) and the compiler warns about it.
struct ReifiedUnsupported: Error {
    let message: String
}

extension JVMFunctionBuilder {
    private static let object: JVMValueType = .reference("java/lang/Object", nullable: true)
    private static let kType: JVMValueType = .reference("kotlin/reflect/KType", nullable: false)

    /// Returns the call target for a classpath reified body: a static method
    /// in a generated class with the call's type arguments substituted. Returns
    /// nil when the method has no marker or a type argument is still open.
    func reifiedClone(of method: JVMForeignMethod, binding: CallBinding?, id: ExprID) throws -> JVMForeignMethod? {
        do {
            return try makeReifiedClone(of: method, binding: binding, id: id)
        } catch let error as ReifiedUnsupported {
            context.diagnostics.warning("KSWIFTK-JVM-REIFIED", error.message + " The call runs the original body, which fails at run time.", range: arena.exprRange(id))
            return nil
        }
    }

    private func makeReifiedClone(of method: JVMForeignMethod, binding: CallBinding?, id: ExprID) throws -> JVMForeignMethod? {
        guard let body = method.reifiedBody, let binding,
              let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee) else { return nil }
        guard !method.isInterface || method.isStatic else {
            throw ReifiedUnsupported(message: "A reified inline function declared in an interface cannot be inlined from the classpath: \(method.owner).\(method.name).")
        }
        let symbols = signature.typeParameterSymbols
        let typeArguments = binding.substitutedTypeArguments
        let selected = symbols.count == typeArguments.count ? symbols : Array(symbols.suffix(typeArguments.count))
        var resolved: [String: TypeID] = [:]
        for (symbol, type) in zip(selected, typeArguments) {
            let actual = program.specialized(type)
            guard isConcreteReifiedArgument(actual) else { return nil }
            guard let name = program.sema.symbols.symbol(symbol).map({ context.interner.resolve($0.name) }) else { continue }
            resolved[name] = actual
        }
        let analysis: JVMReifiedBody.Analysis
        do { analysis = try body.analyze() } catch {
            throw ReifiedUnsupported(message: "Cannot read the classpath body of \(method.owner).\(method.name).")
        }
        let display = method.owner.replacingOccurrences(of: "/", with: ".") + "." + method.name
        if let reason = analysis.unsupported {
            throw ReifiedUnsupported(message: "Cannot inline the reified classpath function \(display): its body uses \(reason).")
        }
        let key = ([method.owner, method.name, method.descriptor] + resolved.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }).joined(separator: "|")
        let descriptor = method.isStatic ? method.descriptor : "(L" + method.owner + ";" + method.descriptor.dropFirst()
        let receiver: [JVMValueType] = method.isStatic ? [] : [.reference(method.owner, nullable: false)]
        func target(_ host: String, _ name: String) -> JVMForeignMethod {
            JVMForeignMethod(
                owner: host, name: name, descriptor: descriptor, parameters: receiver + method.parameters,
                result: method.result, isStatic: true, isInterface: false, isAbstract: false
            )
        }
        if let existing = program.reifiedHosts[key], let clone = existing.clone { return target(existing.name, clone.name) }

        var host = JVMReifiedHost()
        var patches: [JVMReifiedClone.Patch] = []
        for site in analysis.sites {
            patches.append(try reifiedPatch(site, arguments: resolved, analysis: analysis, host: &host, display: display, id: id))
        }
        // The class is named by its content, so independently built modules that
        // clone the same body differently cannot shadow one another's class.
        // A non-public type argument is only nameable from its own package.
        let packages = Set(host.referencedClasses.filter { !program.isPubliclyAccessible($0) }.map { name -> String in
            var plain = name
            while plain.hasPrefix("[") { plain.removeFirst() }
            if plain.hasPrefix("L"), plain.hasSuffix(";") { plain = String(plain.dropFirst().dropLast()) }
            return plain.contains("/") ? String(plain[..<plain.lastIndex(of: "/")!]) : ""
        })
        guard packages.count <= 1 else {
            throw ReifiedUnsupported(message: "Cannot inline the reified classpath function \(display): its type arguments are non-public classes of different packages.")
        }
        let package = packages.first ?? "kswiftk/reified"
        let cloneName = method.name + "$reified"
        let clone = JVMReifiedClone(name: cloneName, descriptor: descriptor, body: body, patches: patches)
        let fingerprint = StableFNV1a64.hex([method.owner, method.name, method.descriptor, String(describing: patches), String(describing: host.helpers.map(\.instructions))].joined(separator: "\u{1}"))
        let shortOwner = method.owner.split(separator: "/").last.map(String.init) ?? method.owner
        host.name = (package.isEmpty ? "" : package + "/") + shortOwner.replacingOccurrences(of: "$", with: "_") + "$Reified$" + fingerprint
        for index in host.helpers.indices { host.helpers[index].owner = host.name }
        host.clone = clone
        program.reifiedHosts[key] = host
        return target(host.name, cloneName)
    }

    private func isConcreteReifiedArgument(_ id: TypeID) -> Bool {
        switch program.sema.types.kind(of: id) {
        case .typeParam: return false
        case let .classType(type):
            return type.args.allSatisfy { argument in
                switch argument {
                case let .invariant(inner), let .out(inner), let .in(inner): return isConcreteReifiedArgument(inner)
                case .star: return true
                }
            }
        default: return true
        }
    }

    private func reifiedPatch(
        _ site: JVMReifiedBody.Site, arguments: [String: TypeID], analysis: JVMReifiedBody.Analysis,
        host: inout JVMReifiedHost, display: String, id: ExprID
    ) throws -> JVMReifiedClone.Patch {
        var identifier = site.identifier
        let markerNullable = identifier.hasSuffix("?")
        if markerNullable { identifier.removeLast() }
        // `[T` names an array whose element is T (Array<T>, Array<Array<T>> ...).
        var dimensions = 0
        while identifier.hasPrefix("[") { identifier.removeFirst(); dimensions += 1 }
        func unsupported(_ detail: String) -> ReifiedUnsupported {
            ReifiedUnsupported(message: "Cannot inline the reified classpath function \(display): \(detail).")
        }
        guard let type = arguments[identifier] else { throw unsupported("type parameter \(identifier) has no concrete type argument") }
        let nullable = markerNullable || (dimensions == 0 && program.sema.types.nullability(of: type) != .nonNull)
        func patch(_ operation: JVMReifiedClone.Operation) -> JVMReifiedClone.Patch {
            JVMReifiedClone.Patch(start: site.start, end: site.end, operation: operation)
        }
        if site.operation == 6, site.placeholderOpcode == 0x01 {
            guard dimensions == 0 else { throw unsupported("typeOf of an array of a type parameter is not supported") }
            // The placeholder is `aconst_null`; a stack map frame that merges only
            // nulls would not accept the KType that replaces it.
            guard !analysis.code.stackMapHasNull else { throw unsupported("its stack map holds null values, which typeOf cannot replace safely") }
            let helper = try reifiedTypeOfHelper(type, nullable: nullable, host: &host, display: display, id: id)
            return patch(.helperCall(name: helper, descriptor: "()Lkotlin/reflect/KType;", checkcast: nil))
        }
        var (className, kotlinName) = try reifiedClassName(type, display: display, id: id)
        for _ in 0..<dimensions {
            className = className.hasPrefix("[") ? "[" + className : "[L" + className + ";"
            kotlinName = "kotlin.Array<" + kotlinName + ">"
        }
        host.referencedClasses.insert(className)
        switch (site.operation, site.placeholderOpcode) {
        case (0, 0xBD): return patch(.anewarray(className))
        case (1, 0xC0):
            return patch(nullable ? .checkcast(className)
                : .checkcastNotNull(className, message: "null cannot be cast to non-null type " + kotlinName))
        case (2, 0xC0):
            let helper = try reifiedHelper("safeCast|" + className, host: &host) { owner, name in
                reifiedCheckHelper(owner, name, className: className, returnsBoolean: false)
            }
            return patch(.helperCall(name: helper, descriptor: "(Ljava/lang/Object;)Ljava/lang/Object;", checkcast: className))
        case (3, 0xC1):
            guard nullable else { return patch(.instanceOf(className)) }
            let helper = try reifiedHelper("isOrNull|" + className, host: &host) { owner, name in
                reifiedCheckHelper(owner, name, className: className, returnsBoolean: true)
            }
            return patch(.helperCall(name: helper, descriptor: "(Ljava/lang/Object;)Z", checkcast: nil))
        case (4, 0x12), (4, 0x13): return patch(.ldcClass(className))
        default:
            throw unsupported("it uses reified operation \(site.operation) in a form that is not supported")
        }
    }

    /// The class named by instanceof/checkcast/ldc for `type`, and its Kotlin
    /// spelling for failure messages. Types whose runtime checks are not a
    /// plain class test (mutable collections, function types) are rejected.
    private func reifiedClassName(_ type: TypeID, display: String, id: ExprID) throws -> (String, String) {
        func unsupported(_ detail: String) -> ReifiedUnsupported {
            ReifiedUnsupported(message: "Cannot inline the reified classpath function \(display): \(detail).")
        }
        if mutableCollectionKind(type) != nil { throw unsupported("a mutable collection type argument needs Kotlin's mutability checks") }
        switch program.sema.types.kind(of: type) {
        case .classType, .stringStruct, .primitive, .any, .unit, .nullableUnit, .platformUnit, .kClassType: break
        default: throw unsupported("the type argument is not a class type")
        }
        let token = try program.classTokenType(type)
        let boxed: JVMValueType = token == .unit ? .reference("kotlin/Unit", nullable: false) : JVMClasspathIndex.boxed(token)
        guard let name = boxed.referenceName, name != "kotlin/jvm/functions/FunctionN",
              !name.hasPrefix("kotlin/jvm/functions/Function") else {
            throw unsupported("a function type argument needs Kotlin's arity checks")
        }
        return (name, castTargetKotlinName(type))
    }

    private func reifiedHelper(
        _ key: String, host: inout JVMReifiedHost, make: (_ owner: String, _ name: String) throws -> JVMFunction
    ) throws -> String {
        if let existing = host.helperNames[key] { return existing }
        let name = "reified$helper$" + String(host.helpers.count)
        host.helpers.append(try make("", name))
        host.helperNames[key] = name
        return name
    }

    /// `x is T?` and `x as? T` need a branch, so they run in a small helper
    /// instead of the fixed-size patch.
    private func reifiedCheckHelper(_ owner: String, _ name: String, className: String, returnsBoolean: Bool) -> JVMFunction {
        let object = Self.object
        let argument = JVMValue(slot: 0, type: object)
        let null = JVMValue(slot: 1, type: object)
        let flag = JVMValue(slot: 2, type: .boolean)
        let result = JVMValue(slot: 3, type: .boolean)
        let notMatching = 0
        var code: [JVMInstruction] = []
        if returnsBoolean {
            code += [
                .constant(.null, null), .referenceCompare(.equal, argument, null, flag), .jumpIfFalse(flag, notMatching),
                .constant(.boolean(true), result), .returnValue(result), .label(notMatching),
                .instanceOf(argument, className, result), .returnValue(result),
            ]
            return program.rawFunction(owner, name: name, parameters: [object], result: .boolean, access: 0x1009, locals: [argument, null, flag, result], instructions: code)
        }
        code += [
            .instanceOf(argument, className, flag), .jumpIfFalse(flag, notMatching), .returnValue(argument),
            .label(notMatching), .constant(.null, null), .returnValue(null),
        ]
        return program.rawFunction(owner, name: name, parameters: [object], result: object, access: 0x1009, locals: [argument, null, flag], instructions: code)
    }

    private func reifiedTypeOfHelper(
        _ type: TypeID, nullable: Bool, host: inout JVMReifiedHost, display: String, id: ExprID
    ) throws -> String {
        let key = "typeOf|\(type.rawValue)|\(nullable)"
        if let existing = host.helperNames[key] { return existing }
        var builder = KTypeBuilder(function: self, display: display, id: id)
        let result = try builder.build(type, nullable: nullable)
        let name = "reified$helper$" + String(host.helpers.count)
        host.helpers.append(program.rawFunction(
            "", name: name, parameters: [], result: Self.kType, access: 0x1009,
            locals: builder.locals, instructions: builder.instructions + [.returnValue(result)]
        ))
        host.helperNames[key] = name
        host.referencedClasses.formUnion(builder.referencedClasses)
        return name
    }

    /// Builds the `Reflection.typeOf` call chain that Kotlin generates for `typeOf<T>()`.
    private struct KTypeBuilder {
        let function: JVMFunctionBuilder
        let display: String
        let id: ExprID
        var instructions: [JVMInstruction] = []
        var locals: [JVMValue] = []
        var referencedClasses: Set<String> = []
        var slot = 0

        init(function: JVMFunctionBuilder, display: String, id: ExprID) {
            self.function = function; self.display = display; self.id = id
        }

        mutating func value(_ type: JVMValueType) -> JVMValue {
            let result = JVMValue(slot: slot, type: type)
            slot += type.width
            locals.append(result)
            return result
        }

        static func method(_ owner: String, _ name: String, _ parameters: [JVMValueType], _ result: JVMValueType) -> JVMForeignMethod {
            JVMForeignMethod(
                owner: owner, name: name, descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor,
                parameters: parameters, result: result, isStatic: true, isInterface: false, isAbstract: false
            )
        }

        mutating func build(_ type: TypeID, nullable: Bool) throws -> JVMValue {
            let program = function.program
            let arguments: [TypeArg]
            switch program.sema.types.kind(of: type) {
            case let .classType(classType): arguments = classType.args
            case .stringStruct, .primitive, .any, .unit, .nullableUnit, .platformUnit, .kClassType: arguments = []
            default:
                throw ReifiedUnsupported(message: "Cannot inline the reified classpath function \(display): typeOf needs a class type.")
            }
            let isNullable = nullable || program.sema.types.nullability(of: type) != .nonNull
            let token = try program.classTokenType(type)
            let classValue = value(.reference("java/lang/Class", nullable: false))
            let primitives: [JVMValueType: String] = [
                .byte: "Byte", .short: "Short", .char: "Character", .int: "Integer",
                .long: "Long", .float: "Float", .double: "Double", .boolean: "Boolean",
            ]
            if !isNullable, let wrapper = primitives[token] {
                instructions.append(.getStatic(JVMField(owner: "java/lang/" + wrapper, name: "TYPE", type: classValue.type, access: 0x19), classValue))
            } else {
                let boxed: JVMValueType = token == .unit ? .reference("kotlin/Unit", nullable: false) : JVMClasspathIndex.boxed(token)
                guard let name = boxed.referenceName else {
                    throw ReifiedUnsupported(message: "Cannot inline the reified classpath function \(display): typeOf needs a class type.")
                }
                referencedClasses.insert(name)
                instructions.append(.classLiteral(name, classValue))
            }
            let projectionType: JVMValueType = .reference("kotlin/reflect/KTypeProjection", nullable: false)
            var projections: [JVMValue] = []
            for argument in arguments {
                let projection = value(projectionType)
                switch argument {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    let variance: String
                    if case .invariant = argument { variance = "invariant" } else if case .out = argument { variance = "covariant" } else { variance = "contravariant" }
                    let innerType = try build(inner, nullable: false)
                    instructions.append(.foreignCall(Self.method("kotlin/reflect/KTypeProjection", variance, [JVMFunctionBuilder.kType], projectionType), receiver: nil, arguments: [innerType], result: projection))
                case .star:
                    instructions.append(.getStatic(JVMField(owner: "kotlin/reflect/KTypeProjection", name: "star", type: projectionType, access: 0x19), projection))
                }
                projections.append(projection)
            }
            let entry = isNullable ? "nullableTypeOf" : "typeOf"
            let result = value(JVMFunctionBuilder.kType)
            let classValueType: JVMValueType = .reference("java/lang/Class", nullable: false)
            if projections.count <= 2 {
                let parameters = [classValueType] + Array(repeating: projectionType, count: projections.count)
                instructions.append(.foreignCall(Self.method("kotlin/jvm/internal/Reflection", entry, parameters, JVMFunctionBuilder.kType), receiver: nil, arguments: [classValue] + projections, result: result))
            } else {
                let arrayType: JVMValueType = .reference("[Lkotlin/reflect/KTypeProjection;", nullable: false)
                let array = value(arrayType)
                let count = value(.int)
                instructions.append(.constant(.int(Int32(projections.count)), count))
                instructions.append(.newArray(projectionType, count: count, result: array))
                for (index, projection) in projections.enumerated() {
                    let position = value(.int)
                    instructions.append(.constant(.int(Int32(index)), position))
                    instructions.append(.arraySet(array, position, projection))
                }
                instructions.append(.foreignCall(Self.method("kotlin/jvm/internal/Reflection", entry, [classValueType, arrayType], JVMFunctionBuilder.kType), receiver: nil, arguments: [classValue, array], result: result))
            }
            return result
        }
    }
}
