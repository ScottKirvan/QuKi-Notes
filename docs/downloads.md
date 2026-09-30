
<script setup>
import { ref, onMounted } from 'vue'
import { useData } from 'vitepress'
//import {BVPlatformButton} from 'bojuvue/vitepress'
import * as BojuVue from 'bojuvue/vitepress'

const { site } = useData()
const manifest = ref(null)

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
      fallback-href="https://github.com/ScottKirvan/BojuVue/releases"
    />
  </div>
<div v-if="manifest" style="font-size: 0.875rem; color: var(--vp-c-text-2); margin: 1rem 0 2.5rem;">
  Latest release: <strong>{{ manifest.version }}</strong>
</div>

</div>


<div style="display: flex; justify-content: center;">
  <table><tbody><tr><td>App
<table style="margin-inline: auto;"><tbody>
  <tr> <td> iOS </td> <td><a href="/QuKi-Notes/install/ios">Instructions</a></td> </tr>
  <tr> <td> Android </td> <td>
  <a href="/QuKi-Notes/install/android">Join The Beta</a><br>
  <a href="/QuKi-Notes/install/android">APK</a>
  </td> </tr>
  <tr> <td> Windows </td> <td><a href="/QuKi-Notes/install/windows">Installer</a></td> </tr>
  <tr> <td> Mac </td> <td><a href="/QuKi-Notes/install/mac">Instructions</a></td> </tr>
  <tr> <td> Linux </td> <td>
  <a href="/QuKi-Notes/install/linux">AppImage</a><br>
  <a href="/QuKi-Notes/install/linux">Snap</a><br>
  <a href="/QuKi-Notes/install/linux">Debian Package</a><br>
  <a href="/QuKi-Notes/install/linux">AppImage (AArch64, ARM64)</a><br>
  <a href="/QuKi-Notes/install/linux">Flatpak (Community maintained)</a>
  </td> </tr>
  <tr> <td> Web </td> <td><a href="/QuKi-Notes/install/web">Get for Web</a></td> </tr>
  </tbody></table>
  </td></tr></tbody></table>
</div>
  

<!--
# Downloads

<div v-if="manifest" style="font-size: 0.875rem; color: var(--vp-c-text-2); margin: 1rem 0 2.5rem;">
  Latest release: <strong>{{ manifest.version }}</strong>
</div>

## Mobile

<div style="display: grid; gap: 1rem; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); margin: 1.5rem 0 2.5rem;">

<div style="border: 1px solid var(--vp-c-divider); border-radius: 8px; padding: 1.25rem;">
  <div style="font-size: 2rem; margin-bottom: 0.5rem;">🤖</div>
  <div style="font-weight: 600; margin-bottom: 0.25rem;">Android</div>
  <div style="font-size: 0.8rem; color: var(--vp-c-text-2); margin-bottom: 1rem;">APK sideload · closed beta</div>
  <a href="/QuKi-Notes/install/android"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Get for Android
  </a>
</div>

</div>

## Desktop

<div style="display: grid; gap: 1rem; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); margin: 1.5rem 0 2.5rem;">

<div style="border: 1px solid var(--vp-c-divider); border-radius: 8px; padding: 1.25rem;">
  <div style="font-size: 2rem; margin-bottom: 0.5rem;">🪟</div>
  <div style="font-weight: 600; margin-bottom: 0.25rem;">Windows</div>
  <div style="font-size: 0.8rem; color: var(--vp-c-text-2); margin-bottom: 1rem;">Installer (.exe) · x64</div>
  <a v-if="manifest" :href="manifest.windows"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download installer
  </a>
  <a v-else href="https://github.com/ScottKirvan/QuKi-Notes/releases/latest" target="_blank"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download installer
  </a>
</div>

<div style="border: 1px solid var(--vp-c-divider); border-radius: 8px; padding: 1.25rem;">
  <div style="font-size: 2rem; margin-bottom: 0.5rem;">🐧</div>
  <div style="font-weight: 600; margin-bottom: 0.25rem;">Linux</div>
  <div style="font-size: 0.8rem; color: var(--vp-c-text-2); margin-bottom: 1rem;">AppImage · x64</div>
  <a v-if="manifest" :href="manifest.linux"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download AppImage
  </a>
  <a v-else href="https://github.com/ScottKirvan/QuKi-Notes/releases/latest" target="_blank"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download AppImage
  </a>
</div>

</div>

## Web

<div style="display: grid; gap: 1rem; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); margin: 1.5rem 0 2.5rem;">

<div style="border: 1px solid var(--vp-c-divider); border-radius: 8px; padding: 1.25rem;">
  <div style="font-size: 2rem; margin-bottom: 0.5rem;">🌐</div>
  <div style="font-weight: 600; margin-bottom: 0.25rem;">Web browser</div>
  <div style="font-size: 0.8rem; color: var(--vp-c-text-2); margin-bottom: 1rem;">No install · QuKis stay in your browser</div>
  <a href="https://www.scottkirvan.com/QuKi-Notes/app/" target="_blank"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Open in browser
  </a>
</div>

</div>

The Windows installer includes optional command-line tools (`quki` and `quki-mcp`), and the Linux AppImage always includes them. See [Command Line & MCP](/command-line/).

<p style="font-size: 0.875rem; color: var(--vp-c-text-2);">
  All releases and changelogs →
  <a href="https://github.com/ScottKirvan/QuKi-Notes/releases" target="_blank">GitHub Releases</a>
</p>




  <div style="display: flex; flex-wrap: wrap; gap: 12px; align-items: center;">
    <BojuVue.BVButton text="Get started" href="https://example.com/get-started" theme="brand" size="big" />
  </div>
-->
