package fixture;

import java.util.TreeSet;

public final class CaseInsensitiveSets {
    public static Object fresh() {
        TreeSet<String> result = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        result.add("a");
        return result;
    }
}
