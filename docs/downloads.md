
<script setup>
import { ref, onMounted } from 'vue'
import { useData } from 'vitepress'
//import {BVPlatformButton} from 'bojuvue/vitepress'
import * as BojuVue from 'bojuvue/vitepress'

const { site } = useData()
const manifest = ref(null)

function download(key) {
  return manifest.value?.[key] ?? 'https://github.com/ScottKirvan/QuKi-Notes/releases/latest'
}

onMounted(async () => {
  try {
    const res = await fetch(`${site.value.base}latest.json`)
    manifest.value = await res.json()
  } catch (e) {}
})
</script>

<div align="center">
<img src="/QuKiNotes_v2_Rainbow_transparent.png" alt="QuKi Notes" width="260" />

# QuKi Notes
&nbsp;
  <div>
    <BojuVue.BVPlatformButton
      manifest-url="/platformButton.json"
      fallback-href="https://github.com/ScottKirvan/QuKi-Notes/releases"
    />
  </div>
<div v-if="manifest" style="font-size: 0.875rem; color: var(--vp-c-text-2); margin: 1rem 0 2.5rem;">
  Latest release: <strong>{{ manifest.version }}</strong>
</div>

</div>


<div style="display: flex; justify-content: center;">
  <table><tbody><tr><td>App
<table style="margin-inline: auto;"><tbody>
  <tr> <td> iOS </td> <td><a href="/QuKi-Notes/install/ios"><i-lucide-book-open /> Instructions</a></td> </tr>
  <tr> <td> Android </td> <td>
  <a href="/QuKi-Notes/install/android"><i-lucide-book-open /> Join The Beta</a><br>
  <a href="https://play.google.com/store/apps/details?id=com.quki.quki_notes"><i-custom-google /> Google Play (Join beta team first)</a><br>
  <a :href="download('android')"><i-lucide-circle-arrow-down /> APK</a>
  </td> </tr>
  <tr> <td> Windows </td> <td><a :href="download('windows')"><i-lucide-circle-arrow-down /> Installer</a></td> </tr>
  <tr> <td> Mac </td> <td><a href="/QuKi-Notes/install/ios"><i-lucide-book-open /> Instructions</a></td> </tr>
  <tr> <td> Linux </td> <td>
  <a :href="download('linux')"><i-lucide-circle-arrow-down /> AppImage</a><br>
  <!-- <a :href="download('linux_snap')"><i-lucide-circle-arrow-down /> Snap</a><br> -->
  <a :href="download('linux_deb')"><i-lucide-circle-arrow-down /> Debian Package</a><br>
  <a :href="download('linux_arm64')"><i-lucide-circle-arrow-down /> AppImage (AArch64, ARM64)</a><br>
  <a :href="download('linux_arm64_deb')"><i-lucide-circle-arrow-down /> Debian Package (AArch64, ARM64)</a>
  <!-- <a :href="download('linux_flatpak')"><i-lucide-circle-arrow-down /> Flatpak (Community maintained)</a> -->
  </td> </tr>
  <tr> <td> Web </td> <td>
  <a href="/QuKi-Notes/install/web"><i-lucide-book-open /> Get for Web</a><br>
  <a href="https://qukinotes.scottkirvan.com/" target="_blank"><i-lucide-globe /> Use in Browser</a>
  </td> </tr>
  </tbody></table>
  </td></tr></tbody></table>
</div>
  

