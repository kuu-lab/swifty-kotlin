package fixture;

import java.util.Arrays;
import java.util.Collections;

public final class MutableCollectionOracle {
    public static Object frozen() {
        return Collections.unmodifiableList(Arrays.asList(1, 2));
    }
}
