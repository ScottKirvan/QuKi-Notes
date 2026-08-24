---
layout: home
hero:
  name: QuKi Notes
  text: Open the app. Type. Done.
  tagline: Scratchpad. Pasteboard. Blank canvas. For the thought that won't wait.
  actions:
    - theme: brand
      text: Get Started
      link: /user-guide/getting-started
    - theme: alt
      text: GitHub
      link: https://github.com/ScottKirvan/QuKi-Notes
features:
  - title: Open and go
    details: Tap the icon, start typing. No title, no template, no folder to pick first.
  - title: Send when ready
    details: Clipboard, share sheet, or any transport you wire up. A QuKi goes somewhere when you decide — not before.
  - title: Plain files, always yours
    details: Every QuKi is a plain .md file on your device. No cloud, no account, no lock-in. Read or move them without ever opening the app.
---

<script setup>
import { ref, onMounted } from 'vue'
import { useData } from 'vitepress'

const { site } = useData()
const manifest = ref(null)
const downloadHref = ref(null)
const downloadLabel = ref(null)

onMounted(async () => {
  try {
    const res = await fetch(`${site.value.base}latest.json`)
    manifest.value = await res.json()
  } catch (e) {}

  if (!manifest.value) return
  const ua = navigator.userAgent
  if (/Android/i.test(ua)) {
    downloadHref.value = '/QuKi-Notes/install/android'
    downloadLabel.value = 'Get for Android'
  } else if (/Win/i.test(navigator.platform)) {
    downloadHref.value = manifest.value.windows
    downloadLabel.value = 'Download for Windows'
  } else if (/Linux/i.test(navigator.platform)) {
    downloadHref.value = manifest.value.linux
    downloadLabel.value = 'Download for Linux'
  }
})
</script>

<div v-if="manifest" style="text-align: center; margin: 2.5rem 0 1.5rem;">
  <a v-if="downloadHref" :href="downloadHref"
     style="display: inline-block; background: var(--vp-c-brand-1); color: var(--vp-c-white); padding: 0.65rem 1.5rem; border-radius: 8px; font-weight: 600; font-size: 1rem; text-decoration: none; margin-bottom: 0.75rem;">
    {{ downloadLabel }}
  </a>
  <div style="font-size: 0.875rem; color: var(--vp-c-text-2); margin-top: 0.5rem;">
    {{ manifest.version }} &nbsp;·&nbsp;
    <a href="/QuKi-Notes/downloads">all platforms</a>
  </div>
</div>

<div style="text-align:center; margin-top: 2rem; font-size: 0.875rem; color: var(--vp-c-text-2);">
  <a href="/QuKi-Notes/privacy">Privacy Policy</a>
</div>

<!-- Begin Sponsors -->

<div align="center" style="margin-top: 3rem; margin-bottom: 2rem;">
<h2>Sponsors</h2>
 <a href="https://www.sabelhawk.com/" target="_blank">
    <img src="/sabelhawk_dark.png" alt="Sabelhawk Studios" width="300" class="sponsor-logo dark-only" />
    <img src="/sabelhawk_lite.png" alt="Sabelhawk Studios" width="300" class="sponsor-logo light-only" />
  </a>
  <h3>Please support open source software:</h3>
  <div style="display: flex; gap: 12px; justify-content: center; align-items: center; flex-wrap: wrap;">
  <a href="https://ko-fi.com/ScottKirvan" target="_blank">
    <img src="https://storage.ko-fi.com/cdn/kofi2.png?v=3" alt="Support on Ko-fi"  width="160"  />
  </a> &nbsp; &nbsp;
  <a href="https://github.com/sponsors/ScottKirvan" target="_blank">
    <img src="https://img.shields.io/badge/Sponsor-GitHub-ea4aaa?style=for-the-badge&logo=github" height="36" />
  </a>
  </div>
  <br>
Thank you! Your help makes a real and direct difference.
</div>

<!-- End Sponsors -->
