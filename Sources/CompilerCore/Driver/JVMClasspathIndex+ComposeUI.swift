import Foundation

extension JVMClasspathIndex {
    static let composeView = "androidx/compose/ui/platform/ComposeView"
    static let mutableIntState = "androidx/compose/runtime/MutableIntState"

    func composeMethod(owner: String, name: String, descriptor: String, isStatic: Bool) -> JVMForeignMethod? {
        guard hasComposeRuntime else { return nil }
        return classes[owner]?.methods.first {
            $0.name == name && $0.descriptor == descriptor && $0.isStatic == isStatic && !$0.isProtected
        }
    }

    var composeContentMethod: JVMForeignMethod? {
        guard composeMethod(owner: JVMCompose.lambdaFacade, name: "composableLambdaInstance",
                            descriptor: "(IZLjava/lang/Object;)Landroidx/compose/runtime/internal/ComposableLambda;",
                            isStatic: true) != nil else { return nil }
        return composeMethod(owner: Self.composeView, name: "setContent",
                             descriptor: "(Lkotlin/jvm/functions/Function2;)V", isStatic: false)
    }

    var composeIntStateFactory: JVMForeignMethod? {
        guard composeMethod(owner: Self.mutableIntState, name: "getIntValue", descriptor: "()I", isStatic: false) != nil,
              composeMethod(owner: Self.mutableIntState, name: "setIntValue", descriptor: "(I)V", isStatic: false) != nil
        else { return nil }
        return composeMethod(owner: "androidx/compose/runtime/SnapshotIntStateKt", name: "mutableIntStateOf",
                             descriptor: "(I)L\(Self.mutableIntState);", isStatic: true)
    }

    func injectComposeUIContracts(into ctx: CompilationContext) {
        func inject(_ path: String, _ source: String, method: JVMForeignMethod, defaultMask: Int32? = nil) {
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            composeStaticContracts[file] = (method, defaultMask)
        }

        if let method = composeIntStateFactory {
            inject("<kswiftk-jvm-import>/compose-int-state.kt", """
                package androidx.compose.runtime
                external fun mutableIntStateOf(value: Int): MutableIntState
                """, method: method)
        }

        // The String overload in Compose Foundation 1.7 has one default mask.
        // Project its text-only form after checking the actual classfile ABI.
        let descriptor = "(Ljava/lang/String;Landroidx/compose/ui/Modifier;Landroidx/compose/ui/text/TextStyle;Lkotlin/jvm/functions/Function1;IZIILandroidx/compose/ui/graphics/ColorProducer;L\(JVMCompose.composer);II)V"
        if let method = composeMethod(owner: "androidx/compose/foundation/text/BasicTextKt", name: "BasicText-VhcvRP8",
                                      descriptor: descriptor, isStatic: true) {
            inject("<kswiftk-jvm-import>/compose-basic-text.kt", """
                package androidx.compose.foundation.text
                @androidx.compose.runtime.Composable external fun BasicText(text: String): Unit
                """, method: method, defaultMask: 0x1FE)
        }
    }
}
