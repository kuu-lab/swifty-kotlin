import kotlinx.io.files.Path

fun requireNonNullParent(): Path = Path("child").parent
