package golden.sema

@Deprecated(
    "Use newApi()",
    ReplaceWith("newApi()", "golden.sema.newApi", "kotlin.io.path.*")
)
fun oldApi(): Int = 1

fun newApi(): Int = 2
