import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildPlatformManifest } from './platformManifest.mjs'

const latest = {
  version: 'v0.25.0',
  windows: 'https://example.test/v0.25.0/quki-notes-windows-v0.25.0.exe',
  linux: 'https://example.test/v0.25.0/QuKi-Notes-x64.AppImage',
}

test('a platform that names a download gets that release URL from latest.json', () => {
  const manifest = buildPlatformManifest(
    { windows: { download: 'windows', label: 'Download for Windows' } },
    latest,
  )
  assert.deepEqual(manifest, {
    platforms: { windows: { href: latest.windows, label: 'Download for Windows' } },
  })
})

test('a platform with a fixed href keeps it, whatever the release', () => {
  const manifest = buildPlatformManifest(
    { android: { href: 'https://example.test/install/android', label: 'Download for Android' } },
    latest,
  )
  assert.deepEqual(manifest, {
    platforms: { android: { href: 'https://example.test/install/android', label: 'Download for Android' } },
  })
})

test('a new release changes only the downloaded links', () => {
  const platforms = {
    linux: { download: 'linux' },
    ios: { href: 'https://example.test/install/ios' },
  }
  const next = { ...latest, linux: 'https://example.test/v0.26.0/QuKi-Notes-x64.AppImage' }
  assert.deepEqual(buildPlatformManifest(platforms, next).platforms, {
    linux: { href: next.linux },
    ios: { href: 'https://example.test/install/ios' },
  })
})

test('naming a download that latest.json does not have fails, naming the platform and key', () => {
  assert.throws(
    () => buildPlatformManifest({ macos: { download: 'macos' } }, latest),
    /macos.*"macos"/,
  )
})

test('a platform with neither a download nor an href fails', () => {
  assert.throws(() => buildPlatformManifest({ ios: { label: 'Download for iOS' } }, latest), /ios/)
})

test('a platform with both a download and an href fails rather than picking one', () => {
  assert.throws(
    () => buildPlatformManifest({ windows: { download: 'windows', href: 'https://example.test/x' } }, latest),
    /windows/,
  )
})
