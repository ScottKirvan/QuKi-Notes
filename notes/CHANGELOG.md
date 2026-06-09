# Changelog

## [0.9.2](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.9.1...v0.9.2) (2026-06-08)


### Bug Fixes

* **editor:** auto-focus editor on launch and add keyboard dismiss button ([3cb93ad](https://github.com/ScottKirvan/QuKi-Notes/commit/3cb93adf537ea9a1ad5db94896d7890f509ada84))
* **ui:** apply Primer Dark High Contrast theme and disable editor auto-capitalization ([d3f3791](https://github.com/ScottKirvan/QuKi-Notes/commit/d3f3791a5c4353652ce66f6091b1ce0e5ba95d9e))

## [0.9.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.9.0...v0.9.1) (2026-06-04)


### Bug Fixes

* chore - force new build ([48a5ea6](https://github.com/ScottKirvan/QuKi-Notes/commit/48a5ea66bffdd32253de82b33088e50d86435374))

## [0.9.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.8.1...v0.9.0) (2026-06-04)


### Features

* **editor:** add *italic* reaction and monospace code styling ([18c4e86](https://github.com/ScottKirvan/QuKi-Notes/commit/18c4e86728ab5dd61edc95eca244d46b75392232))
* **editor:** live inline markdown input reactions ([a0e5dde](https://github.com/ScottKirvan/QuKi-Notes/commit/a0e5dde89d20b71f11b8e3247ca382424c86e8db)), closes [#27](https://github.com/ScottKirvan/QuKi-Notes/issues/27)


### Bug Fixes

* **docs:** clarify cross-platform support in README ([befe16f](https://github.com/ScottKirvan/QuKi-Notes/commit/befe16fb90b06936ee72cc1d2399ee5f47ecc896))
* **docs:** correct British English spellings to American English ([6e5093c](https://github.com/ScottKirvan/QuKi-Notes/commit/6e5093cf1f6e5c02b60e010a8258433b8e4e60bd))
* **docs:** update CONTRIBUTING, issue templates, and add philosophy page ([b749aff](https://github.com/ScottKirvan/QuKi-Notes/commit/b749aff8788c56ac5335e48351d467d6bb74ce67))
* **editor:** restore heading sizes overridden by BlockSelector.all rule ([da0edd4](https://github.com/ScottKirvan/QuKi-Notes/commit/da0edd4c29941574091d16c2a3c5da7083e936a7))
* **editor:** wire super_editor markdown serializer for correct round-trip ([1b2fa1d](https://github.com/ScottKirvan/QuKi-Notes/commit/1b2fa1decce1936f3d1b61009a044834b16732da))

## [0.8.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.8.0...v0.8.1) (2026-06-04)


### Bug Fixes

* **docs:** rewrite README as a complete GitHub landing page ([111f37a](https://github.com/ScottKirvan/QuKi-Notes/commit/111f37a4026f290e145f818caf369795a2a8ec85))
* **docs:** write full user-facing VitePress documentation ([cfdda0c](https://github.com/ScottKirvan/QuKi-Notes/commit/cfdda0c2d5f09924433f589354b2151067108d34))
* **ui:** editor is permanent root — one editor, always ([7aa312f](https://github.com/ScottKirvan/QuKi-Notes/commit/7aa312f9687a5fa732b3663b93ab1cfc838058dc))

## [0.8.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.7.0...v0.8.0) (2026-06-04)


### Features

* **ui:** editor navigation redesign — QuKis icon, hamburger menu, Send terminology ([c3da627](https://github.com/ScottKirvan/QuKi-Notes/commit/c3da6271dc64ef201a142f111d62dd731c7239b7))


### Bug Fixes

* **ci:** fix dart format — reorder lucide import, wrap long lines ([4234389](https://github.com/ScottKirvan/QuKi-Notes/commit/4234389d2f2c5f37c2862d5b792cc43c01dbd9ab))
* publish docs - vitepress - workflow was broken ([f4a9e7f](https://github.com/ScottKirvan/QuKi-Notes/commit/f4a9e7fe334fa2e0c20ad403d98a5c1427f00e86))
* **stream:** guarantee undo snackbar dismissal via explicit Timer ([6baa553](https://github.com/ScottKirvan/QuKi-Notes/commit/6baa553d00b25b82978809f2c980a0dfd6519215))
* **ui:** auto-dismiss snackbars and fix paragraph double-spacing ([8818a07](https://github.com/ScottKirvan/QuKi-Notes/commit/8818a072de3a14323495fd67d81fd2b9a68352d8))
* **ui:** fix undo snackbar dismiss and paragraph blank-line round-trip ([c6942c6](https://github.com/ScottKirvan/QuKi-Notes/commit/c6942c666ed50dbdb50aea1c60aec918f46b34b9))

## [0.7.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.6.2...v0.7.0) (2026-06-03)


### Features

* **desktop:** keyboard shortcuts for Windows + Linux ([9cb3814](https://github.com/ScottKirvan/QuKi-Notes/commit/9cb381478f66d3f56a2d63c86bd7b13246e3f31a))
* **desktop:** window-state persistence via window_manager ([4f5b373](https://github.com/ScottKirvan/QuKi-Notes/commit/4f5b3738ca3a17e09ea767eaaf13ebe67fca171c))


### Bug Fixes

* **desktop:** remove Escape shortcut from editor ([a869334](https://github.com/ScottKirvan/QuKi-Notes/commit/a8693342330b1def4d4b241807db5c765744af09))

## [0.6.2](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.6.1...v0.6.2) (2026-06-03)


### Bug Fixes

* **share_in:** guard receive_sharing_intent behind Platform.isAndroid ([60b4c99](https://github.com/ScottKirvan/QuKi-Notes/commit/60b4c99381cf4448591dab95d4b58bdf577e3681))

## [0.6.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.6.0...v0.6.1) (2026-06-03)


### Bug Fixes

* **ci:** remove push:tags trigger to prevent duplicate builds ([1433079](https://github.com/ScottKirvan/QuKi-Notes/commit/143307936c96700c175eaaa7628217bc9fdb015e))

## [0.6.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.5.0...v0.6.0) (2026-06-03)


### Features

* **share_in:** Android text share-in via receive_sharing_intent ([723ed4d](https://github.com/ScottKirvan/QuKi-Notes/commit/723ed4dfaa1135d568d5488f70472d91adba9903))


### Bug Fixes

* **android:** align JVM target to 17 across all plugin subprojects ([d6f5345](https://github.com/ScottKirvan/QuKi-Notes/commit/d6f534532f98ef33c379b33d8a8b21ec24f063c9))
* **android:** set compileOptions in LibraryExtension to fix JVM mismatch ([26a0f73](https://github.com/ScottKirvan/QuKi-Notes/commit/26a0f7368f6b3259f1762b3539c9cfec81ca809f))
* **justfile:** use powershell.exe shebang for android recipe ([998cd36](https://github.com/ScottKirvan/QuKi-Notes/commit/998cd36d8119f70ba9c99ed84eedb8965696ca33))

## [0.5.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.4.0...v0.5.0) (2026-06-03)


### Features

* **transports:** Phase 2 — transport plugin architecture + clipboard + share sheet ([a9cd632](https://github.com/ScottKirvan/QuKi-Notes/commit/a9cd632c7db17b5412c9c3abd59a5cd105bf2419))

## [0.4.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.3.0...v0.4.0) (2026-06-02)


### Features

* **settings:** Phase 1.6 settings stub + package_info_plus for version ([c5dddf5](https://github.com/ScottKirvan/QuKi-Notes/commit/c5dddf5d42722f3b3cbe5f1db47e3ccba47efea4))

## [0.3.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.2.0...v0.3.0) (2026-06-02)


### Features

* **editor:** auto-save controller + sort stream by modifiedAt ([041192f](https://github.com/ScottKirvan/QuKi-Notes/commit/041192f43bc6cb55482ae19afcc69b9e70a20d38))

## [0.2.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.1.0...v0.2.0) (2026-06-02)


### Features

* **editor:** add ← Stream nav, save-on-leave bridge, and paragraph restore ([6a0d7ba](https://github.com/ScottKirvan/QuKi-Notes/commit/6a0d7ba3a8e8346855792849f0baa83f9e140c26))
* **stream:** add stream screen with list, search, swipe-delete, and undo ([b55178c](https://github.com/ScottKirvan/QuKi-Notes/commit/b55178c83607663c1f9baf32d31dd0c2eddec208))

## 0.1.0 (2026-06-01)


### Features

* **database:** add drift schema v1 — qukis + images tables, DAOs, providers ([654cd14](https://github.com/ScottKirvan/QuKi-Notes/commit/654cd149c25098fcb427b82266ac938b00e30eeb))
* **editor:** add editor screen with super_editor and formatting toolbar ([18a8f8a](https://github.com/ScottKirvan/QuKi-Notes/commit/18a8f8a41afc7993d015020f4c7261cdb9d42847))


### Bug Fixes

* **android:** force compileSdk 36 for all library subprojects ([bf77157](https://github.com/ScottKirvan/QuKi-Notes/commit/bf7715744424584fcd871a78661344c21fede405))
* **android:** set compileSdk 36 for super_keyboard compatibility ([747f031](https://github.com/ScottKirvan/QuKi-Notes/commit/747f031eac97d8517d08efca07f935f7d3af12ad))
* build workflow test - update code-workspace file. ([4a01708](https://github.com/ScottKirvan/QuKi-Notes/commit/4a01708b73114eaca3b326208a69238730d8b495))
* **editor:** force cursor white for testing ([d284ef8](https://github.com/ScottKirvan/QuKi-Notes/commit/d284ef81fe6d1d41e767051b5a77ef1e218f7fa8))
* **editor:** set cursor color to colorScheme.primary for visibility ([77d360f](https://github.com/ScottKirvan/QuKi-Notes/commit/77d360fd5a3aa85f17ee418546821a5de1b698e8))
* **editor:** theme-aware text color and toolbar above keyboard ([4afa539](https://github.com/ScottKirvan/QuKi-Notes/commit/4afa539d53399b0e3360a6fbb72dbe1a7b2da532))
* **editor:** use SuperEditorAndroidControlsScope for visible cursor ([abfaaf8](https://github.com/ScottKirvan/QuKi-Notes/commit/abfaaf8de35f795cadf70b027286a3260241cfe9))

## Changelog
>[!NOTE]
> This file and it's version format is automatically 
> generated by [Please-Release](https://github.com/googleapis/release-please-action), 
> and adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
