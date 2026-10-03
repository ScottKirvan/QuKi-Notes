import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitepress'
import { bojuvue } from 'bojuvue/vite'
import Icons from 'unplugin-icons/vite'
import { FileSystemIconLoader } from 'unplugin-icons/loaders'
import IconsResolver from 'unplugin-icons/resolver'
import Components from 'unplugin-vue-components/vite'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import { platformManifestPlugin } from '../scripts/platformManifest.mjs'
import { resolveFeatureIcons, withCurrentColorFill } from '../scripts/featureIcons.mjs'

const customIconsDir = fileURLToPath(new URL('./icons', import.meta.url))

export default defineConfig({
  title: 'QuKi-Notes',
  description: 'Capture ephemeral notes, frictionlessly.',
  base: '/QuKi-Notes/',
  srcExclude: ['**/_*.md'],
  transformPageData(pageData) {
    resolveFeatureIcons(pageData.frontmatter, { customDir: customIconsDir, page: pageData.relativePath })
  },
  markdown: {
    config(md) {
      md.use(tabsMarkdownPlugin)
    },
  },
  vite: {
    plugins: [
      bojuvue(),
      platformManifestPlugin({
        platformsFile: fileURLToPath(new URL('../platforms.json', import.meta.url)),
        latestFile: fileURLToPath(new URL('../public/latest.json', import.meta.url)),
      }),
      Components({
        dirs: [],
        include: [/\.vue$/, /\.vue\?vue/, /\.md$/],
        resolvers: [IconsResolver({ customCollections: ['custom'] })],
        dts: false,
      }),
      Icons({
        defaultClass: 'icon',
        customCollections: {
          custom: FileSystemIconLoader(customIconsDir, withCurrentColorFill),
        },
      }),
    ],
  },
  themeConfig: {
    nav: [
      { text: 'User Guide', link: '/user-guide/getting-started' },
      { text: 'CLI & MCP', link: '/command-line/' },
      { text: 'Downloads', link: '/downloads' },
    ],
    sidebar: [
      {
        text: 'User Guide',
        items: [
          { text: 'Getting Started', link: '/user-guide/getting-started' },
          { text: 'Capturing QuKis', link: '/user-guide/capturing-qukis' },
          { text: 'QuKis List', link: '/user-guide/qukis-list' },
          { text: 'Sending QuKis', link: '/user-guide/sending-qukis' },
          { text: 'Settings', link: '/user-guide/settings' },
          { text: 'Keyboard Shortcuts', link: '/user-guide/keyboard-shortcuts' },
          { text: 'Why QuKi-Notes Works This Way', link: '/user-guide/philosophy' },
        ],
      },
      {
        text: 'Command Line & MCP',
        items: [
          { text: 'CLI & MCP Reference', link: '/command-line/' },
          { text: 'quki (CLI)', link: '/command-line/cli' },
          { text: 'quki-mcp (MCP server)', link: '/command-line/mcp' },
        ],
      },
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/ScottKirvan/QuKi-Notes' },
    ],
    search: {
      provider: 'local'
    },
  },
})
