import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { PLACEHOLDER, findPlaceholders } from './placeholders.mjs'

function withDocsTree(files, run) {
  const root = mkdtempSync(join(tmpdir(), 'placeholders-'))
  try {
    for (const [path, content] of Object.entries(files)) {
      mkdirSync(join(root, path, '..'), { recursive: true })
      writeFileSync(join(root, path), content)
    }
    run(root)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

test('reports nothing when no page has a placeholder', () => {
  withDocsTree({ 'index.md': '# Home\n', 'user-guide/settings.md': 'Settings\n' }, (root) => {
    assert.deepEqual(findPlaceholders(root), [])
  })
})

test('reports every placeholder with its file and line, in nested folders too', () => {
  withDocsTree(
    {
      'index.md': `# Home\n${PLACEHOLDER}\n`,
      'user-guide/settings.md': `one\r\ntwo\r\nscreenshot: ${PLACEHOLDER}\r\n`,
    },
    (root) => {
      const found = findPlaceholders(root).sort((a, b) => a.file.localeCompare(b.file))
      assert.deepEqual(found, [
        { file: 'index.md', line: 2 },
        { file: 'user-guide/settings.md', line: 3 },
      ])
    },
  )
})

test('scans Vue components, including the VitePress theme', () => {
  withDocsTree({ '.vitepress/theme/Widget.vue': `<template>${PLACEHOLDER}</template>\n` }, (root) => {
    assert.deepEqual(findPlaceholders(root), [{ file: '.vitepress/theme/Widget.vue', line: 1 }])
  })
})

test('ignores dependencies, VitePress build output and non-page files', () => {
  withDocsTree(
    {
      'node_modules/pkg/README.md': PLACEHOLDER,
      '.vitepress/dist/index.md': PLACEHOLDER,
      '.vitepress/cache/page.md': PLACEHOLDER,
      'public/notes.txt': PLACEHOLDER,
    },
    (root) => {
      assert.deepEqual(findPlaceholders(root), [])
    },
  )
})
