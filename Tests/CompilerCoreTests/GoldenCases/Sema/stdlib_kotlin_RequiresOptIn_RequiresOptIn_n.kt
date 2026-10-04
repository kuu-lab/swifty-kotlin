package golden.sema

@kotlin.RequiresOptIn(
    message = "experimental",
    level = kotlin.RequiresOptIn.Level.WARNING
)
annotation class RequiresOptInMarker

fun useRequiresOptInMarker() {}
