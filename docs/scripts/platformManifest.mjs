import { readFileSync } from 'node:fs'

export const MANIFEST_FILE = 'platformButton.json'

export function buildPlatformManifest(platforms, latest) {
  const resolved = {}
  for (const [platform, { download, href, ...rest }] of Object.entries(platforms)) {
    if (download !== undefined && href !== undefined) {
      throw new Error(`platforms.json: ${platform} has both "download" and "href"; give it one`)
    }
    if (download !== undefined) {
      if (!latest[download]) {
        throw new Error(`platforms.json: ${platform} names download "${download}", which latest.json does not have`)
      }
      resolved[platform] = { href: latest[download], ...rest }
    } else if (href !== undefined) {
      resolved[platform] = { href, ...rest }
    } else {
      throw new Error(`platforms.json: ${platform} needs a "download" or an "href"`)
    }
  }
  return { platforms: resolved }
}

const readJson = (path) => JSON.parse(readFileSync(path, 'utf-8'))

// Serves platformButton.json in dev and writes it into the build, so it is
// never a committed file that could drift from latest.json.
export function platformManifestPlugin({ platformsFile, latestFile }) {
  const render = () =>
    JSON.stringify(buildPlatformManifest(readJson(platformsFile), readJson(latestFile)), null, 2)
  let ssr = false
  return {
    name: 'quki-platform-manifest',
    configResolved(config) {
      ssr = Boolean(config.build.ssr)
    },
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (!req.url?.split('?')[0].endsWith(`/${MANIFEST_FILE}`)) return next()
        res.setHeader('Content-Type', 'application/json')
        res.end(render())
      })
    },
    generateBundle() {
      if (!ssr) this.emitFile({ type: 'asset', fileName: MANIFEST_FILE, source: render() })
    },
  }
}
