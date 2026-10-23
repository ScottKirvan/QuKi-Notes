package com.quki.quki_notes;

import android.os.Bundle;
import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.PluginHandle;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(StoragePlugin.class);
        registerPlugin(SharePlugin.class);
        registerPlugin(ShareInPlugin.class);
        registerPlugin(WindowFocusPlugin.class);
        super.onCreate(savedInstanceState);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        Bridge bridge = getBridge();
        if (bridge == null) return;
        PluginHandle handle = bridge.getPlugin("WindowFocus");
        if (handle == null) return;
        ((WindowFocusPlugin) handle.getInstance()).onWindowFocusChanged(hasFocus);
    }
}
