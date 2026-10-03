import { readdirSync, readFileSync } from 'node:fs'
import { join, relative } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

export const PLACEHOLDER = 'GORILLATITS'

const SKIPPED_DIRS = ['node_modules', '.vitepress/cache', '.vitepress/dist']
const SCANNED_EXTENSIONS = ['.md', '.vue']

export function findPlaceholders(root) {
  const found = []
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name)
      const file = relative(root, path).replaceAll('\\', '/')
      if (entry.isDirectory()) {
        if (!SKIPPED_DIRS.some((skip) => file === skip || file.endsWith(`/${skip}`))) walk(path)
      } else if (SCANNED_EXTENSIONS.some((ext) => entry.name.endsWith(ext))) {
        readFileSync(path, 'utf-8')
          .split(/\r?\n/)
          .forEach((text, i) => {
            if (text.includes(PLACEHOLDER)) {
              found.push({ file, line: i + 1 })
            }
          })
      }
    }
  }
  walk(root)
  return found
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const docsRoot = fileURLToPath(new URL('..', import.meta.url))
  const found = findPlaceholders(docsRoot)
  if (found.length > 0) {
    for (const { file, line } of found) console.error(`${file}:${line}: ${PLACEHOLDER} placeholder`)
    console.error(`\n${found.length} ${PLACEHOLDER} placeholder(s) left in the docs.`)
    process.exit(1)
  }
}
