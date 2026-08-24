# Downloads

<script setup>
import { ref, onMounted } from 'vue'
import { useData } from 'vitepress'

const { site } = useData()
const manifest = ref(null)

onMounted(async () => {
  try {
    const res = await fetch(`${site.value.base}latest.json`)
    manifest.value = await res.json()
  } catch (e) {}
})
</script>

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
  <div style="font-size: 0.8rem; color: var(--vp-c-text-2); margin-bottom: 1rem;">MSI installer · x64</div>
  <a v-if="manifest" :href="manifest.windows"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download MSI
  </a>
  <a v-else href="https://github.com/ScottKirvan/QuKi-Notes/releases/latest" target="_blank"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download MSI
  </a>
</div>

<div style="border: 1px solid var(--vp-c-divider); border-radius: 8px; padding: 1.25rem;">
  <div style="font-size: 2rem; margin-bottom: 0.5rem;">🐧</div>
  <div style="font-weight: 600; margin-bottom: 0.25rem;">Linux</div>
  <div style="font-size: 0.8rem; color: var(--vp-c-text-2); margin-bottom: 1rem;">tar.gz · x64</div>
  <a v-if="manifest" :href="manifest.linux"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download tar.gz
  </a>
  <a v-else href="https://github.com/ScottKirvan/QuKi-Notes/releases/latest" target="_blank"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.5rem 1rem; border-radius: 6px; font-size: 0.875rem; text-decoration: none;">
    Download tar.gz
  </a>
</div>

</div>

<p style="font-size: 0.875rem; color: var(--vp-c-text-2);">
  All releases and changelogs →
  <a href="https://github.com/ScottKirvan/QuKi-Notes/releases" target="_blank">GitHub Releases</a>
</p>
