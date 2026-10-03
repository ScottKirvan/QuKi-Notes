import { existsSync, readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { getIconData, iconToHTML, iconToSVG } from '@iconify/utils'

const require = createRequire(import.meta.url)
let lucide

function lucideSvg(name) {
  lucide ??= JSON.parse(readFileSync(require.resolve('@iconify-json/lucide/icons.json'), 'utf-8'))
  const data = getIconData(lucide, name)
  if (!data) return null
  const { attributes, body } = iconToSVG(data)
  return iconToHTML(body, attributes)
}

function customSvg(name, customDir) {
  const path = join(customDir, `${name}.svg`)
  return existsSync(path) ? withCurrentColorFill(readFileSync(path, 'utf-8').trim()) : null
}

// Brand logos (e.g. from Simple Icons) ship without a fill; Lucide-style SVGs
// that set fill="none" keep it.
export function withCurrentColorFill(svg) {
  return /<svg[^>]*\sfill=/.test(svg) ? svg : svg.replace('<svg', '<svg fill="currentColor"')
}

// Frontmatter is data, not a Vue template, so `<i-lucide-… />` tags can't
// work there; this swaps `lucide:name` / `custom:name` feature icons for the
// SVG markup the default theme renders as HTML.
export function resolveFeatureIcons(frontmatter, { customDir, page }) {
  if (!Array.isArray(frontmatter.features)) return
  for (const feature of frontmatter.features) {
    const match = typeof feature.icon === 'string' && /^(lucide|custom):(.+)$/.exec(feature.icon)
    if (!match) continue
    const [, set, name] = match
    const svg = set === 'lucide' ? lucideSvg(name) : customSvg(name, customDir)
    if (!svg) throw new Error(`${page}: unknown feature icon "${feature.icon}"`)
    feature.icon = svg
  }
}
