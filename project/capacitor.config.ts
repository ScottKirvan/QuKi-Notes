import type { CapacitorConfig } from "@capacitor/cli";

/**
 * appId must stay "com.quki.quki_notes" - the existing Play-Store-approved
 * Flutter app's applicationId (confirmed in ../android/app/build.gradle.kts).
 * This Capacitor project ships under that same listing, not a new one, so
 * changing this later would sever the connection to the existing install
 * base and the already-approved all-files storage permission.
 */
const config: CapacitorConfig = {
  appId: "com.quki.quki_notes",
  appName: "QuKi Notes",
  webDir: "dist",
};

export default config;
