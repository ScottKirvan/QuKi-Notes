package com.quki.quki_notes;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(StoragePlugin.class);
        registerPlugin(SharePlugin.class);
        registerPlugin(ShareInPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
