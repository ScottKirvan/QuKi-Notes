import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'QuKi-Notes',
  description: 'Capture ephemeral notes, frictionlessly.',
  base: '/QuKi-Notes/',
  srcExclude: ['**/_*.md'],
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
          { text: 'Overview & Setup', link: '/command-line/' },
          { text: 'quki (CLI)', link: '/command-line/cli' },
          { text: 'quki-mcp (MCP server)', link: '/command-line/mcp' },
        ],
      },
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/ScottKirvan/QuKi-Notes' },
    ],
  },
})
