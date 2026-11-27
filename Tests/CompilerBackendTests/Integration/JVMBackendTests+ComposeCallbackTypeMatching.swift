#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension JVMBackendTests {
    @Test
    func importedComposableCallbackTypesMatchKClassAndArrayProjections() throws {
        let context = try semaContext(from: """
        fun kClassString(callback: (kotlin.reflect.KClass<String>) -> Unit) {}
        fun kClassInt(callback: (kotlin.reflect.KClass<Int>) -> Unit) {}
        fun arrayInString(callback: (Array<in String>) -> Unit) {}
        fun arrayString(callback: (Array<String>) -> Unit) {}
        """)
        let sema = try #require(context.sema)

        func callbackType(_ functionName: String) throws -> TypeID {
            let symbol = try #require(sema.symbols.allSymbols().first {
                $0.kind == .function && context.interner.resolve($0.name) == functionName
            })
            let signature = try #require(sema.symbols.functionSignatureIfKnown(for: symbol.id))
            return try #require(signature.parameterTypes.first)
        }

        let kClassString = try callbackType("kClassString")
        let kClassInt = try callbackType("kClassInt")
        let arrayInString = try callbackType("arrayInString")
        let arrayString = try callbackType("arrayString")
        let owner = "fixture/CallbackTypes"
        let descriptor = "(Lkotlin/jvm/functions/Function3;)V"

        func named(_ name: String, arguments: [JVMKotlinTypeArgument] = []) -> JVMKotlinType {
            .named(name, arguments, nullable: false)
        }

        func callback(_ input: JVMKotlinType) -> JVMKotlinType {
            .function([input], named("kotlin/Unit"), receiver: nil, nullable: false, isComposable: true)
        }

        func function(_ jvmName: String, _ type: JVMKotlinType) -> JVMKotlinFunctionInfo {
            JVMKotlinFunctionInfo(
                name: "render", jvmName: jvmName, descriptor: descriptor, flags: 6,
                typeParameters: [], receiver: nil,
                parameters: [.init(name: "callback", type: type, varargType: nil, hasDefault: false)],
                result: named("kotlin/Unit")
            )
        }

        func method(_ name: String) -> JVMForeignMethod {
            JVMForeignMethod(
                owner: owner, name: name, descriptor: descriptor,
                parameters: [.reference("kotlin/jvm/functions/Function3", nullable: false)],
                result: .unit, isStatic: false, isInterface: true, isAbstract: true
            )
        }

        let functions = [
            function("renderKClassString", callback(named("kotlin/reflect/KClass", arguments: [
                .init(type: named("kotlin/String"), variance: 2)
            ]))),
            function("renderKClassInt", callback(named("kotlin/reflect/KClass", arguments: [
                .init(type: named("kotlin/Int"), variance: 2)
            ]))),
            function("renderArrayInString", callback(named("kotlin/Array", arguments: [
                .init(type: named("kotlin/String"), variance: 0)
            ]))),
            function("renderArrayString", callback(named("kotlin/Array", arguments: [
                .init(type: named("kotlin/String"), variance: 2)
            ])))
        ]
        let methods = functions.map { method($0.jvmName) }
        let index = JVMClasspathIndex()
        index.classes[owner] = JVMClassInfo(
            name: owner, flags: 0x0200, superclass: "java/lang/Object", interfaces: [], methods: methods
        )
        index.kotlinMetadataByClass[owner] = JVMKotlinClassMetadata(
            classFlags: 0, companion: nil, typeParameters: [], functions: functions,
            properties: [], typeAliases: [], isPackage: false
        )

        func matches(_ methodName: String, _ sourceType: TypeID) -> Bool {
            guard let method = methods.first(where: { $0.name == methodName }) else { return false }
            return index.matchesComposableCallbackTypes(
                method, sourceTypes: [sourceType], callbackParameters: [0], sema: sema, ctx: context
            )
        }

        #expect(matches("renderKClassString", kClassString))
        #expect(!matches("renderKClassString", kClassInt))
        #expect(matches("renderKClassInt", kClassInt))
        #expect(!matches("renderKClassInt", kClassString))
        #expect(matches("renderArrayInString", arrayInString))
        #expect(!matches("renderArrayInString", arrayString))
        #expect(matches("renderArrayString", arrayString))
        #expect(!matches("renderArrayString", arrayInString))
    }

    @Test
    func methodLevelComposableOverloadsMatchCallbackArity() throws {
        let context = try semaContext(from: """
        fun oneArgument(callback: (String) -> Unit) {}
        fun twoArguments(callback: (String, Int) -> Unit) {}
        fun threeArguments(callback: (String, Int, Boolean) -> Unit) {}
        """)
        let sema = try #require(context.sema)

        func callbackType(_ functionName: String) throws -> TypeID {
            let symbol = try #require(sema.symbols.allSymbols().first {
                $0.kind == .function && context.interner.resolve($0.name) == functionName
            })
            let signature = try #require(sema.symbols.functionSignatureIfKnown(for: symbol.id))
            return try #require(signature.parameterTypes.first)
        }

        let oneArgument = try callbackType("oneArgument")
        let twoArguments = try callbackType("twoArguments")
        let threeArguments = try callbackType("threeArguments")
        let owner = "fixture/MethodComposable"
        let descriptor = "(Lkotlin/jvm/functions/Function1;Landroidx/compose/runtime/Composer;I)V"
        let physicalParameters: [JVMValueType] = [
            .reference("kotlin/jvm/functions/Function1", nullable: false),
            JVMCompose.composerType,
            .int
        ]

        func functionType(_ inputs: [JVMKotlinType]) -> JVMKotlinType {
            .function(inputs, .named("kotlin/Unit", [], nullable: false), receiver: nil, nullable: false)
        }

        func info(_ jvmName: String, _ type: JVMKotlinType, descriptor: String) -> JVMKotlinFunctionInfo {
            JVMKotlinFunctionInfo(
                name: "render", jvmName: jvmName, descriptor: descriptor, flags: 6,
                typeParameters: [], receiver: nil,
                parameters: [.init(name: "callback", type: type, varargType: nil, hasDefault: false)],
                result: .named("kotlin/Unit", [], nullable: false)
            )
        }

        func method(_ jvmName: String, _ sourceType: String) -> JVMForeignMethod {
            var method = JVMForeignMethod(
                owner: owner, name: jvmName, descriptor: descriptor, parameters: physicalParameters,
                result: .unit, isStatic: false, isInterface: true, isAbstract: true
            )
            method.annotations = [JVMAnnotation(descriptor: "Landroidx/compose/runtime/Composable;", visible: false)]
            method.kotlinFunction = JVMKotlinFunction(
                name: "render", jvmName: jvmName, descriptor: descriptor, result: "kotlin.Unit",
                parameters: [.init(name: "callback", sourceType: sourceType, isVararg: false, hasDefaultValue: false)],
                typeParameters: [], contextParameters: [], receiver: nil, isSuspend: false
            )
            return method
        }

        let firstInfo = info("renderOne", functionType([.named("kotlin/String", [], nullable: false)]), descriptor: descriptor)
        let secondInfo = info("renderTwo", functionType([
            .named("kotlin/String", [], nullable: false), .named("kotlin/Int", [], nullable: false)
        ]), descriptor: descriptor)
        let plainDescriptor = "(Lkotlin/jvm/functions/Function3;)V"
        let plainInfo = info("renderPlain", functionType([
            .named("kotlin/String", [], nullable: false), .named("kotlin/Int", [], nullable: false),
            .named("kotlin/Boolean", [], nullable: false)
        ]), descriptor: plainDescriptor)
        var methods = [
            method("renderOne", "(kotlin.String) -> kotlin.Unit"),
            method("renderTwo", "(kotlin.String, kotlin.Int) -> kotlin.Unit"),
            JVMForeignMethod(
                owner: owner, name: "renderPlain", descriptor: plainDescriptor,
                parameters: [.reference("kotlin/jvm/functions/Function3", nullable: false)],
                result: .unit, isStatic: false, isInterface: true, isAbstract: true
            )
        ]
        methods[2].kotlinFunction = JVMKotlinFunction(
            name: "render", jvmName: "renderPlain", descriptor: plainDescriptor, result: "kotlin.Unit",
            parameters: [.init(
                name: "callback", sourceType: "(kotlin.String, kotlin.Int, kotlin.Boolean) -> kotlin.Unit",
                isVararg: false, hasDefaultValue: false
            )],
            typeParameters: [], contextParameters: [], receiver: nil, isSuspend: false
        )
        let index = JVMClasspathIndex()
        index.classes[owner] = JVMClassInfo(
            name: owner, flags: 0x0200, superclass: "java/lang/Object", interfaces: [], methods: methods
        )
        index.kotlinMetadataByClass[owner] = JVMKotlinClassMetadata(
            classFlags: 0, companion: nil, typeParameters: [], functions: [firstInfo, secondInfo, plainInfo],
            properties: [], typeAliases: [], isPackage: false
        )

        #expect(index.matchesComposeMemberStub(
            methods[0], sourceName: "render", sourceTypes: [oneArgument], composableParameters: [], sema: sema, ctx: context
        ))
        #expect(!index.matchesComposeMemberStub(
            methods[1], sourceName: "render", sourceTypes: [oneArgument], composableParameters: [], sema: sema, ctx: context
        ))
        #expect(!index.matchesComposeMemberStub(
            methods[0], sourceName: "render", sourceTypes: [twoArguments], composableParameters: [], sema: sema, ctx: context
        ))
        #expect(index.matchesComposeMemberStub(
            methods[1], sourceName: "render", sourceTypes: [twoArguments], composableParameters: [], sema: sema, ctx: context
        ))
        #expect(!index.matchesComposeMemberStub(
            methods[0], sourceName: "render", sourceTypes: [threeArguments], composableParameters: [], sema: sema, ctx: context
        ))
        #expect(!index.matchesComposeMemberStub(
            methods[2], sourceName: "render", sourceTypes: [threeArguments], composableParameters: [], sema: sema, ctx: context
        ))
    }
}
#endif
