package org.swiftykotlin.composeprobe;

import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.compose.runtime.Composer;
import androidx.compose.runtime.MutableState;
import androidx.compose.runtime.SnapshotStateKt;
import androidx.compose.ui.Modifier;
import androidx.compose.ui.viewinterop.AndroidView_androidKt;
import kotlin.Unit;

public final class CounterRenderer {
    private final MutableState<Integer> count =
        SnapshotStateKt.mutableStateOf(0, SnapshotStateKt.structuralEqualityPolicy());

    public void render(Composer composer, String prefix) {
        AndroidView_androidKt.AndroidView(context -> {
            LinearLayout layout = new LinearLayout(context);
            layout.setOrientation(LinearLayout.VERTICAL);
            TextView label = new TextView(context);
            Button increment = new Button(context);
            increment.setText("Increment");
            increment.setOnClickListener(view -> count.setValue(count.getValue() + 1));
            layout.addView(label);
            layout.addView(increment);
            return layout;
        }, Modifier.Companion, layout -> {
            ((TextView) layout.getChildAt(0)).setText(prefix + ": " + count.getValue());
            return Unit.INSTANCE;
        }, composer, 0, 0);
    }
}
