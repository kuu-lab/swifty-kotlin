/// Resolves bindings as graph methods. Scoped methods cache their value on
/// the graph instance under the same monitor, including nullable results.
final class JVMMetroBindingEmitter {
    private let program: JVMProgramBuilder
    private let implementation: String
    private let graph: JVMClassPlan
    private let range: SourceRange
    private let scopes: Set<String>
    private var bindings: [JVMMetroBindingKey: [JVMMetroBinding]]
    private var pending: Set<JVMMetroBindingKey> = []
    private var resolved: [JVMMetroBindingKey: JVMForeignMethod] = [:]
    private var nextBindingIndex = 0
    private var modules: [String: String] = [:]
    private(set) var methods: [JVMFunction] = []
    private(set) var fields: [JVMField] = []
    private(set) var classes: [JVMClass] = []

    init(program: JVMProgramBuilder, graph: JVMClassPlan, implementation: String, range: SourceRange,
         scopes: Set<String>, bindings: [JVMMetroBindingKey: [JVMMetroBinding]]) {
        self.program = program
        self.graph = graph
        self.implementation = implementation
        self.range = range
        self.scopes = scopes
        self.bindings = bindings
    }

    func entry(_ method: JVMForeignMethod, key: JVMMetroBindingKey) throws -> JVMFunction {
        let binding = try resolve(key)
        let builder = try makeBuilder(method.name, result: method.result)
        let receiver = try builder.value(.reference(implementation, nullable: false))
        let result = try invoke(binding, on: receiver, using: builder)
        builder.instructions.append(.returnValue(try builder.convert(result, to: method.result)))
        return finish(builder, access: 0x0011)
    }

    private func resolve(_ key: JVMMetroBindingKey) throws -> JVMForeignMethod {
        if let method = resolved[key] { return method }
        guard pending.insert(key).inserted else { throw fail("has a dependency cycle at \(key)") }
        defer { pending.remove(key) }
        let candidates = bindings[key] ?? []
        let binding: JVMMetroBinding
        if candidates.count == 1, let candidate = candidates.first {
            binding = candidate
        } else if candidates.isEmpty, key.qualifiers.isEmpty,
                  key.type.hasPrefix("L"), key.type.hasSuffix(";"), !key.type.contains("<"),
                  let constructor = try program.metroConstructorBinding(String(key.type.dropFirst().dropLast())) {
            binding = constructor
        } else {
            throw fail(candidates.isEmpty ? "cannot resolve binding for \(key)" : "has multiple bindings for \(key)")
        }
        if let scope = binding.scope, !scopes.contains(scope) {
            throw fail("cannot resolve \(key) scoped to \(scope)")
        }
        let name = "$metroBinding" + String(nextBindingIndex)
        nextBindingIndex += 1
        let builder = try makeBuilder(name, result: binding.type)
        let receiver = try builder.value(.reference(implementation, nullable: false))
        let cache: (JVMField, JVMField)?
        if binding.scope != nil {
            let value = JVMField(owner: implementation, name: name + "Value", type: binding.type, access: 0x0002)
            let initialized = JVMField(owner: implementation, name: name + "Initialized", type: .boolean, access: 0x0002)
            fields += [value, initialized]
            let compute = builder.label()
            let isInitialized = try builder.value(.boolean)
            builder.instructions += [.getField(initialized, receiver, isInitialized), .jumpIfFalse(isInitialized, compute)]
            let cached = try builder.value(value.type)
            builder.instructions += [.getField(value, receiver, cached), .returnValue(cached)]
            builder.mark(compute)
            cache = (value, initialized)
        } else {
            cache = nil
        }
        let result = try builder.convert(emit(binding.recipe, receiver: receiver, using: builder), to: binding.type)
        if let (field, initialized) = cache {
            let flag = try builder.constant(.boolean(true), .boolean)
            builder.instructions += [.putField(field, receiver, result), .putField(initialized, receiver, flag)]
        }
        builder.instructions.append(.returnValue(result))
        methods.append(finish(builder, access: cache == nil ? 0x0010 : 0x0030))
        let method = JVMForeignMethod(owner: implementation, name: name, descriptor: "()" + binding.type.descriptor,
                                      parameters: [], result: binding.type, isStatic: false, isInterface: false, isAbstract: false)
        resolved[key] = method
        return method
    }

    private func emit(_ recipe: JVMMetroBinding.Recipe, receiver: JVMValue, using builder: JVMFunctionBuilder) throws -> JVMValue {
        func dependency(_ key: JVMMetroBindingKey) throws -> JVMValue {
            try invoke(resolve(key), on: receiver, using: builder)
        }
        switch recipe {
        case let .input(field):
            let value = try builder.value(field.type)
            builder.instructions.append(.getField(field, receiver, value))
            return value
        case let .alias(key):
            return try dependency(key)
        case let .constructor(method, dependencies):
            let args = try zip(dependencies, method.parameters).map { key, type in try builder.convert(dependency(key), to: type) }
            let value = try builder.value(method.result)
            builder.instructions += [.allocate(method.owner, value), .foreignCall(method, receiver: value, arguments: args, result: nil)]
            return value
        case let .provider(method, owner, dependencies):
            let instance = try owner.map { try module($0, using: builder) }
            let values = try dependencies.map(dependency)
            let inputs = method.isStatic ? (instance.map { [$0] } ?? []) + values : values
            let arguments = try zip(inputs, method.parameters).map { try builder.convert($0, to: $1) }
            let result = try builder.value(method.result)
            builder.instructions.append(.foreignCall(method, receiver: method.isStatic ? nil : instance, arguments: arguments, result: result))
            return result
        case let .set(elements):
            let set = try builder.constructJDK("java/util/LinkedHashSet")
            let object = JVMValueType.reference("java/lang/Object", nullable: true)
            for key in elements {
                _ = try builder.jdkCall("java/util/LinkedHashSet", "add", [object], .boolean,
                                        receiver: set, arguments: [dependency(key)])
            }
            return set
        }
    }

    private func module(_ owner: String, using builder: JVMFunctionBuilder) throws -> JVMValue {
        if let info = program.context.jvmImports?.metroClassInfo(owner),
           info.fields.contains(where: { $0.name == "INSTANCE" && $0.isPublic && $0.isStatic && $0.descriptor == "L" + owner + ";" }) {
            let type = JVMValueType.reference(owner, nullable: false)
            let result = try builder.value(type)
            builder.instructions.append(.getStatic(JVMField(owner: owner, name: "INSTANCE", type: type, access: 0x0019), result))
            return result
        }
        if let source = program.classes.values.first(where: { $0.name == owner }), source.isObject {
            return try builder.singleton(source)
        }
        let name: String
        if let module = modules[owner] {
            name = module
        } else {
            guard program.classes.values.contains(where: { $0.name == owner && $0.isInterface })
                    || program.context.jvmImports?.metroClassInfo(owner)?.isInterface == true else {
                throw fail("cannot instantiate provider owner \(owner)")
            }
            name = implementation + "$Module" + String(modules.count)
            modules[owner] = name
            classes.append(program.rawClass(name, interfaces: [owner], access: 0x0030,
                                            functions: [program.metroConstructor(name, fields: [])]))
        }
        return try builder.constructJDK(name)
    }

    private func makeBuilder(_ name: String, result: JVMValueType) throws -> JVMFunctionBuilder {
        let declaration = FunDecl(range: range, name: program.context.interner.intern(name), modifiers: [], valueParams: [], body: .unit)
        return JVMFunctionBuilder(program: program, declaration: declaration,
                                  reference: JVMFunctionReference(name: name, parameters: [], result: result))
    }

    private func finish(_ builder: JVMFunctionBuilder, access: UInt16) -> JVMFunction {
        var function = program.rawFunction(implementation, name: builder.reference.name, parameters: [],
                                           result: builder.reference.result, access: access,
                                           locals: builder.locals, instructions: builder.instructions)
        function.checksParameters = false
        return function
    }

    private func invoke(_ method: JVMForeignMethod, on receiver: JVMValue, using builder: JVMFunctionBuilder) throws -> JVMValue {
        let result = try builder.value(method.result)
        builder.instructions.append(.foreignCall(method, receiver: receiver, arguments: [], result: result))
        return result
    }

    private func fail(_ message: String) -> JVMFrontendError {
        JVMFrontendError(message: "Metro graph \(graph.name) \(message).", range: range)
    }
}
