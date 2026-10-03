import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { resolveFeatureIcons, withCurrentColorFill } from './featureIcons.mjs'

function withCustomIcons(files, run) {
  const dir = mkdtempSync(join(tmpdir(), 'feature-icons-'))
  try {
    for (const [name, svg] of Object.entries(files)) writeFileSync(join(dir, name), svg)
    run(dir)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

test('a lucide: icon becomes the Lucide SVG markup, drawn in currentColor', () => {
  withCustomIcons({}, (customDir) => {
    const frontmatter = { features: [{ icon: 'lucide:plus', title: 'Capture' }] }
    resolveFeatureIcons(frontmatter, { customDir, page: 'index.md' })
    const { icon, title } = frontmatter.features[0]
    assert.equal(title, 'Capture')
    assert.match(icon, /^<svg[^>]*viewBox="0 0 24 24"/)
    assert.match(icon, /stroke="currentColor"/)
    assert.match(icon, /<\/svg>$/)
  })
})

test('a custom: icon becomes that file from the custom icons folder', () => {
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M0 0h24"/></svg>'
  withCustomIcons({ 'mark.svg': svg }, (customDir) => {
    const frontmatter = { features: [{ icon: 'custom:mark' }] }
    resolveFeatureIcons(frontmatter, { customDir, page: 'index.md' })
    assert.equal(frontmatter.features[0].icon, withCurrentColorFill(svg))
  })
})

test('emoji, raw SVG and image icons, and features without an icon, are left alone', () => {
  withCustomIcons({}, (customDir) => {
    const image = { src: '/logo.svg', width: '32' }
    const features = [{ icon: '⚡' }, { icon: '<svg></svg>' }, { icon: image }, { title: 'no icon' }]
    const frontmatter = { features: structuredClone(features) }
    resolveFeatureIcons(frontmatter, { customDir, page: 'index.md' })
    assert.deepEqual(frontmatter.features, features)
  })
})

test('a page without features is left alone', () => {
  withCustomIcons({}, (customDir) => {
    const frontmatter = { title: 'Downloads' }
    resolveFeatureIcons(frontmatter, { customDir, page: 'downloads.md' })
    assert.deepEqual(frontmatter, { title: 'Downloads' })
  })
})

test('an unknown lucide icon fails, naming the page and the icon', () => {
  withCustomIcons({}, (customDir) => {
    const frontmatter = { features: [{ icon: 'lucide:no-such-icon' }] }
    assert.throws(() => resolveFeatureIcons(frontmatter, { customDir, page: 'index.md' }), /index\.md.*lucide:no-such-icon/)
  })
})

test('a missing custom icon fails, naming the page and the icon', () => {
  withCustomIcons({}, (customDir) => {
    const frontmatter = { features: [{ icon: 'custom:missing' }] }
    assert.throws(() => resolveFeatureIcons(frontmatter, { customDir, page: 'index.md' }), /index\.md.*custom:missing/)
  })
})

test('withCurrentColorFill adds a currentColor fill only to an SVG without one', () => {
  assert.equal(withCurrentColorFill('<svg viewBox="0 0 1 1"></svg>'), '<svg fill="currentColor" viewBox="0 0 1 1"></svg>')
  assert.equal(withCurrentColorFill('<svg fill="none"></svg>'), '<svg fill="none"></svg>')
})
