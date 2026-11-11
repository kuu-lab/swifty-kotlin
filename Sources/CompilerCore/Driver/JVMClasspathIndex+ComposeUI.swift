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

    private var hasComposableLambdaFactory: Bool {
        composeMethod(owner: JVMCompose.lambdaFacade, name: "composableLambdaInstance",
                      descriptor: "(IZLjava/lang/Object;)Landroidx/compose/runtime/internal/ComposableLambda;",
                      isStatic: true) != nil
    }

    var composeContentMethod: JVMForeignMethod? {
        guard hasComposableLambdaFactory else { return nil }
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
        func inject(_ path: String, _ source: String, method: JVMForeignMethod, composable: JVMCompose.ImportedCall? = nil) {
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            composeStaticContracts[file] = (method, composable)
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
                """, method: method, composable: .init(defaultMask: 0x1FE))
        }

        guard hasComposableLambdaFactory else { return }
        // Compose 1.7 Column has three defaulted parameters before its required content.
        let columnDescriptor = "(Landroidx/compose/ui/Modifier;Landroidx/compose/foundation/layout/Arrangement$Vertical;Landroidx/compose/ui/Alignment$Horizontal;Lkotlin/jvm/functions/Function3;L\(JVMCompose.composer);II)V"
        if classes["androidx/compose/foundation/layout/ColumnScope"] != nil,
           let method = composeMethod(owner: "androidx/compose/foundation/layout/ColumnKt", name: "Column",
                                      descriptor: columnDescriptor, isStatic: true) {
            inject("<kswiftk-jvm-import>/compose-column.kt", """
                package androidx.compose.foundation.layout
                @androidx.compose.runtime.Composable external fun Column(content: @androidx.compose.runtime.Composable ColumnScope.() -> Unit): Unit
                """, method: method, composable: .init(defaultMask: 0x7, contentParameter: 0))
        }

        // Material 3 1.3 Button keeps its click callback and content explicit.
        let buttonDescriptor = "(Lkotlin/jvm/functions/Function0;Landroidx/compose/ui/Modifier;ZLandroidx/compose/ui/graphics/Shape;Landroidx/compose/material3/ButtonColors;Landroidx/compose/material3/ButtonElevation;Landroidx/compose/foundation/BorderStroke;Landroidx/compose/foundation/layout/PaddingValues;Landroidx/compose/foundation/interaction/MutableInteractionSource;Lkotlin/jvm/functions/Function3;L\(JVMCompose.composer);II)V"
        if classes["androidx/compose/foundation/layout/RowScope"] != nil,
           let method = composeMethod(owner: "androidx/compose/material3/ButtonKt", name: "Button",
                                      descriptor: buttonDescriptor, isStatic: true) {
            inject("<kswiftk-jvm-import>/compose-button.kt", """
                package androidx.compose.material3
                @androidx.compose.runtime.Composable external fun Button(onClick: () -> Unit, content: @androidx.compose.runtime.Composable androidx.compose.foundation.layout.RowScope.() -> Unit): Unit
                """, method: method, composable: .init(defaultMask: 0x1FE, contentParameter: 1))
        }
    }
}
