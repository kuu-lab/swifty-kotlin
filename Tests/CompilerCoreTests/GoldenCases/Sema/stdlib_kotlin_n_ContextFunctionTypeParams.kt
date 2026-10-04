package golden.sema

fun useContextFunctionTypeParams(
    action: @ContextFunctionTypeParams(2) @ExtensionFunctionType Function4<String, Int, Double, Byte, Unit>,
    block: @ContextFunctionTypeParams(count = 1) Function2<String, Byte, Unit>
) {}
