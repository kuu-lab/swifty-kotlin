import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeMetadataAPITests {
    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cString in
            cString.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    @Test func metadataSerializationRoundTrip() throws {
        let metadata = KotlinMetadata(
            functions: [
                KmFunction(
                    name: "greet",
                    returnType: "kotlin.String",
                    valueParameters: [
                        KmValueParameter(name: "name", type: "kotlin.String")
                    ],
                    annotations: [
                        KmAnnotation(className: "sample.Logged", arguments: ["level=debug"])
                    ],
                    isSuspend: false,
                    typeSignature: "(kotlin.String) -> kotlin.String"
                )
            ],
            constructors: [
                KmConstructor(
                    valueParameters: [
                        KmValueParameter(name: "name", type: "kotlin.String")
                    ],
                    annotations: [
                        KmAnnotation(className: "sample.Inject")
                    ],
                    isPrimary: true,
                    visibility: "PUBLIC",
                    declaringClassName: "sample.Greeter"
                )
            ],
            annotations: [
                KmAnnotation(className: "sample.FileAnno", arguments: ["enabled=true"])
            ],
            compilerPlugins: [
                KmCompilerPluginMetadata(
                    pluginId: "sample.plugin",
                    version: "1.2.3",
                    data: ["mode": "strict"]
                )
            ]
        )

        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(metadata)
        let serialized = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(KotlinMetadata.self, from: data)

        #expect(decoded == metadata)
        #expect(serialized.contains("\"pluginId\":\"sample.plugin\""))
    }

    @Test func deserializeRejectsInvalidJSON() {
        let data = Data("{not-json}".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(KotlinMetadata.self, from: data)
        }
    }

    @Test func kmFunctionCanBeBuiltFromRuntimeBoxes() throws {
        let parameterRaw = __kk_kparameter_create(
            0,
            makeRuntimeString("value"),
            makeRuntimeString("kotlin.Int"),
            1,
            2
        )
        let parameterList = registerRuntimeObject(RuntimeListBox(elements: [parameterRaw]))
        let functionRaw = __kk_kfunction_create_full(
            makeRuntimeString("plusOne"),
            1,
            makeRuntimeString("kotlin.Int"),
            0,
            0,
            0,
            parameterList,
            makeRuntimeString("(kotlin.Int) -> kotlin.Int")
        )

        let functionBox = try #require(
            runtimeObject(functionRaw, as: RuntimeKFunctionBox.self),
            "Expected RuntimeKFunctionBox"
        )

        let metadata = KmFunction(functionBox, annotations: [KmAnnotation(className: "sample.Test")])
        #expect(metadata.name == "plusOne")
        #expect(metadata.returnType == "kotlin.Int")
        #expect(metadata.valueParameters.count == 1)
        #expect(metadata.valueParameters.first?.name == "value")
        #expect(metadata.valueParameters.first?.isOptional == true)
        #expect(metadata.typeSignature == "(kotlin.Int) -> kotlin.Int")
        #expect(metadata.annotations.map(\.className) == ["sample.Test"])
    }

    @Test func kmConstructorCanBeBuiltFromRuntimeBoxes() {
        let classEntry = RuntimeKClassMetadataEntry(
            qualifiedName: "sample.Person",
            simpleName: "Person",
            supertypeName: nil,
            isDataClass: true,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 2,
            memberCount: 3,
            constructorCount: 1,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 501, entry: classEntry)
        let kclassRaw = __kk_kclass_create(501, makeRuntimeString("Person"))

        let box = RuntimeKConstructorBox(
            nameRaw: makeRuntimeString("<init>"),
            arity: 2,
            returnTypeRaw: makeRuntimeString("sample.Person"),
            fnPtr: 0,
            isPrimary: true,
            visibilityRaw: makeRuntimeString("PUBLIC"),
            declaringClassRaw: kclassRaw,
            parameterNameRaws: [makeRuntimeString("name"), makeRuntimeString("age")]
        )

        let metadata = KmConstructor(box, annotations: [KmAnnotation(className: "sample.Inject")])
        #expect(metadata.name == "<init>")
        #expect(metadata.declaringClassName == "sample.Person")
        #expect(metadata.valueParameters.map(\.name) == ["name", "age"])
        #expect(metadata.visibility == "PUBLIC")
        #expect(metadata.isPrimary)
        #expect(metadata.annotations.map(\.className) == ["sample.Inject"])
    }

    @Test func findAssociatedObjectReturnsNullWhenNoRuntimeHandleIsRecorded() {
        var classEntry = RuntimeKClassMetadataEntry(
            qualifiedName: "sample.Host",
            simpleName: "Host",
            supertypeName: nil,
            isDataClass: false,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 0,
            memberCount: 0,
            constructorCount: 0,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        classEntry.annotations = [
            RuntimeAnnotationRecord(annotationFQName: "sample.Binding", arguments: ["value=sample.Associated::class"]),
        ]
        runtimeKClassMetadataRegistry.register(typeToken: 90210, entry: classEntry)

        let kclassRaw = __kk_kclass_create(90210, makeRuntimeString("Host"))
        let result = __kk_kclass_find_associated_object(kclassRaw, makeRuntimeString("Binding"))

        #expect(result == runtimeNullSentinelInt)
    }

    private func runtimeObject<T: AnyObject>(_ raw: Int, as type: T.Type) -> T? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return nil
        }
        return tryCast(ptr, to: type)
    }
}
