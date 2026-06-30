# Changelog

## [0.14.8](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.7...v0.14.8) (2026-06-30)


### Bug Fixes

* use gh release list for tag lookup instead of target_commitish filter ([8a85d4b](https://github.com/ScottKirvan/QuKi-Notes/commit/8a85d4b4cb6d75c375c39e0c6ab94e1a473f7efa))

## [0.14.7](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.6...v0.14.7) (2026-06-30)


### Bug Fixes

* move Discord notify to after all builds complete ([c7d790d](https://github.com/ScottKirvan/QuKi-Notes/commit/c7d790dbd2938efae62c22f207fc9cdaaef4dd33))

## [0.14.6](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.5...v0.14.6) (2026-06-30)


### Reverts

* **editor:** remove autofocus: true — made keyboard worse on Android ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([0957d30](https://github.com/ScottKirvan/QuKi-Notes/commit/0957d30a3b62e2d6de696e58fbaee6a7f3595957))

## [0.14.5](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.4...v0.14.5) (2026-06-30)


### Bug Fixes

* **editor:** keyboard on cold launch + stop resume rescan dropping IME ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([98aebd0](https://github.com/ScottKirvan/QuKi-Notes/commit/98aebd01c0266c5e172ef1a20bc078735c2ce1c3))

## [0.14.4](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.3...v0.14.4) (2026-06-30)


### Bug Fixes

* **editor:** remove keyboard auto-focus hacks — let Android handle IME ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([91a206c](https://github.com/ScottKirvan/QuKi-Notes/commit/91a206cca471ac92933078e918cd62f5d27640e9))

## [0.14.3](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.2...v0.14.3) (2026-06-30)


### Bug Fixes

* **editor:** delay focusFirstBlock 150ms to wait for IME ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([ad9b13b](https://github.com/ScottKirvan/QuKi-Notes/commit/ad9b13be61f1657b90de397ecaa265f33c7fb9c8))

## [0.14.2](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.1...v0.14.2) (2026-06-30)


### Bug Fixes

* add shared release notes and Discord notify workflows ([ff30ea5](https://github.com/ScottKirvan/QuKi-Notes/commit/ff30ea58c0d8bee0cbaa446647eb0aedfb181cb4))

## [0.14.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.0...v0.14.1) (2026-06-30)


### Bug Fixes

* update Discord invite URL to correct server link ([b94acc0](https://github.com/ScottKirvan/QuKi-Notes/commit/b94acc0d620bd12d082766abeaf8466a7b3d170b))

## [0.14.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.13.1...v0.14.0) (2026-06-30)


### Features

* **editor:** edit mode preference + keyboard on launch ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([f19eaee](https://github.com/ScottKirvan/QuKi-Notes/commit/f19eaee0a58b0bff591870c8ef3eac2aab11e6c4))
* **storage:** first-launch storage location choice (ADR-27, closes [#134](https://github.com/ScottKirvan/QuKi-Notes/issues/134)) ([536787c](https://github.com/ScottKirvan/QuKi-Notes/commit/536787c66ab0e6d93adaba86f88c394ae8b172ce))
* **storage:** MANAGE_EXTERNAL_STORAGE approach for Android filesystem storage (ADR-28) ([e85173e](https://github.com/ScottKirvan/QuKi-Notes/commit/e85173ef662ef7480ac0d7ec25de8cea106695b1))


### Bug Fixes

* remove GitHub Discussions link, keep Discord only in issue template config ([51cfc8c](https://github.com/ScottKirvan/QuKi-Notes/commit/51cfc8c4fa21b8310b9980b47ffcd48ae57a59a2))
* **storage:** downgrade file_picker to 8.3.7, fix API call, add upgrade detection ([2fba542](https://github.com/ScottKirvan/QuKi-Notes/commit/2fba5429b67cf04ed253fef3752714ccb1410515))
* **storage:** reactive provider cascade — QuKi list updates immediately after location choice ([73490eb](https://github.com/ScottKirvan/QuKi-Notes/commit/73490eb3ac78d73ef2a486374b8942a25c140081))

## [0.13.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.13.0...v0.13.1) (2026-06-25)


### Bug Fixes

* **editor:** adjust checkbox vertical offset to 5px ([77bd32a](https://github.com/ScottKirvan/QuKi-Notes/commit/77bd32ace3ec7acb06e3e40ad3ff53da8ee5ed61))
* **editor:** bypass MarkdownBody for bare task items to prevent assertion crash ([#138](https://github.com/ScottKirvan/QuKi-Notes/issues/138)) ([8891822](https://github.com/ScottKirvan/QuKi-Notes/commit/8891822a1c1935c9bae839d69561f841c4fb42f1))
* **editor:** remove keyboard dismiss button; nudge checkbox alignment ([28875d5](https://github.com/ScottKirvan/QuKi-Notes/commit/28875d5739b403717684970ab247743f0842ad8d))
* **editor:** render all task items directly, bypassing flutter_markdown task list ([151413b](https://github.com/ScottKirvan/QuKi-Notes/commit/151413b58bf96bc31be9ddef6264e947711a6da5))
* **test:** remove dismissKeyboard test — method removed in [#132](https://github.com/ScottKirvan/QuKi-Notes/issues/132) ([f951aa7](https://github.com/ScottKirvan/QuKi-Notes/commit/f951aa7569c8fe15b27883e5ce9501ca2da03369))

## [0.13.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.12.0...v0.13.0) (2026-06-25)


### Features

* **assets:** add v2 icon source files, remove superseded originals ([d496495](https://github.com/ScottKirvan/QuKi-Notes/commit/d49649574dbda4b057db2902a0c98c1919277544))
* **assets:** update app icon to QuKiNotes v2 Rainbow ([d9e6975](https://github.com/ScottKirvan/QuKi-Notes/commit/d9e69757a83c5cd2140a6380f18e8666a2200a13))

## [0.12.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.11.0...v0.12.0) (2026-06-20)


### Features

* **editor:** task checkbox tap, keyboard navigation, flip animations (ADR-26 stage 4) ([acee992](https://github.com/ScottKirvan/QuKi-Notes/commit/acee99248f91076457fd2a0126b54e805d20c7e6))


### Bug Fixes

* **assets:** increase adaptive icon inset to 8% ([5928211](https://github.com/ScottKirvan/QuKi-Notes/commit/59282114cecab1cbd92bf028de3c35427a151940))
* **assets:** reduce adaptive icon inset from 16% to 6% ([82ba985](https://github.com/ScottKirvan/QuKi-Notes/commit/82ba9850dc3f14c789bd2e15345dab91a2d9bd08))
* **assets:** restore default 16% adaptive icon inset ([b9a0ba7](https://github.com/ScottKirvan/QuKi-Notes/commit/b9a0ba72ccaedd02a1c8cf6a12f696ee9dd41ea1))
* **assets:** set adaptive icon background color, remove auto-inset ([e0a769b](https://github.com/ScottKirvan/QuKi-Notes/commit/e0a769ba27f108b6781f6f2d91d902d19f4fa525))
* **editor:** left-align AnimatedSwitcher crossfade + test fix ([d2e51bc](https://github.com/ScottKirvan/QuKi-Notes/commit/d2e51bcf41bd094ece3b27b84b4c6fe02eacdd01))

## [0.11.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.10.1...v0.11.0) (2026-06-20)


### Features

* **editor:** block-flip WYSIWYG rendering (ADR-26 stage 3) ([c3e42b1](https://github.com/ScottKirvan/QuKi-Notes/commit/c3e42b12ad6f01c93ae94befe4c4ec8c51d3590c))


### Bug Fixes

* **editor:** autofocus block enters edit mode on first frame (ADR-26 stage 3) ([b71cbf4](https://github.com/ScottKirvan/QuKi-Notes/commit/b71cbf4a42080ade2057acb1fcdcf7bad8d67998))
* **editor:** checkbox rendering, block stuck in edit mode (ADR-26 stage 3) ([c66c908](https://github.com/ScottKirvan/QuKi-Notes/commit/c66c9087d242c35bfcfbfdb2c92b24dd5d1cda5f))
* **editor:** guard MarkdownBody against bare list-prefix blocks ([c4b0a6c](https://github.com/ScottKirvan/QuKi-Notes/commit/c4b0a6cda8f05a58e4ef403e1537c6ba54f557ce))
* **editor:** new-note focus, toolbar on existing notes, double Enter (ADR-26 stage 3) ([683ae04](https://github.com/ScottKirvan/QuKi-Notes/commit/683ae04eebb63e0ed1e93637c1f50d17d61e6796))
* **editor:** reduce block spacing, prevent double-split on Android IME ([16fce2d](https://github.com/ScottKirvan/QuKi-Notes/commit/16fce2d8eea3b94e09dc2323335cd173f962be9e))
* **editor:** remove minHeight from non-empty blocks to fix double-spacing (ADR-26 stage 3) ([35d8548](https://github.com/ScottKirvan/QuKi-Notes/commit/35d8548a5382004589fe3c9a920874b254b56306))
* **editor:** render bare list markers via zero-width space instead of blank ([1546f30](https://github.com/ScottKirvan/QuKi-Notes/commit/1546f305685ee46b9c0ab0f3abba3cfd3fc522da))
* **editor:** toolbar, autofocus keyboard, list auto-continue (ADR-26 stage 3) ([4b92fda](https://github.com/ScottKirvan/QuKi-Notes/commit/4b92fda653a9e95ffccdfd13e2ac7c0fcdf60106))

## [0.10.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.10.0...v0.10.1) (2026-06-18)


### Bug Fixes

* Change app label from 'quki_notes' to 'QuKi Notes' ([a13e159](https://github.com/ScottKirvan/QuKi-Notes/commit/a13e15989e828631af130f81ea54a35bcb6e4bd1))

## [0.10.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.9.6...v0.10.0) (2026-06-18)


### Features

* **editor:** add markdown_live_editor monorepo package (ADR-26 stage 1) ([06fc4e8](https://github.com/ScottKirvan/QuKi-Notes/commit/06fc4e846cd0a5193b61599a5d28e21db9064fb7))
* **editor:** add unordered and ordered list toolbar buttons (ADR-26 stage 2) ([3bb0461](https://github.com/ScottKirvan/QuKi-Notes/commit/3bb04611ec5c5c71c586ac530b45b90ae2ebbf91))
* **editor:** formatting toolbar and list auto-continue (ADR-26 stage 2) ([3224409](https://github.com/ScottKirvan/QuKi-Notes/commit/322440956f22acc3a476f0ff3598f4ec4fbb0f3e))


### Bug Fixes

* **editor:** restore FormattingToolbar and keyboard toggle (stage 1 stub) ([647338d](https://github.com/ScottKirvan/QuKi-Notes/commit/647338db1cd71221625a9816ade49c7a1cbfa8a4))
* **ios:** extend mobile platform guards to include iOS ([ebf3e86](https://github.com/ScottKirvan/QuKi-Notes/commit/ebf3e8629e5f57e301316aedf3f2182f2987b713))

## [0.9.6](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.9.5...v0.9.6) (2026-06-15)


### Bug Fixes

* **editor:** guard Android cursor controls to Android only ([#76](https://github.com/ScottKirvan/QuKi-Notes/issues/76)) ([993637d](https://github.com/ScottKirvan/QuKi-Notes/commit/993637d9aaa1df32d35c6f121de24bfa80fae6c6))
* **editor:** set caret color from theme so cursor is visible in dark mode ([#76](https://github.com/ScottKirvan/QuKi-Notes/issues/76)) ([7588d3e](https://github.com/ScottKirvan/QuKi-Notes/commit/7588d3e88cfb8cef6343db4340f9d28c025b5e16))
* **theme:** shrink checkbox touch target for tighter task list spacing ([b56a47d](https://github.com/ScottKirvan/QuKi-Notes/commit/b56a47d2be3db341cffa4aa6948fa0744ea0abc4))

## [0.9.5](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.9.4...v0.9.5) (2026-06-15)


### Bug Fixes

* **editor:** keyboard toggle, toolbar disable-on-no-selection, task list node insertion (#post-96, Bugs 3+4+5) ([c445b0c](https://github.com/ScottKirvan/QuKi-Notes/commit/c445b0c84c0e3968a9fe6fe906ae994fea28c9b6))
* **editor:** prevent spurious mtime bumps on QuKi open ([#75](https://github.com/ScottKirvan/QuKi-Notes/issues/75)) ([ceece57](https://github.com/ScottKirvan/QuKi-Notes/commit/ceece57b572b2a3ba6d74991fcca0e1944ef6170))
* **editor:** use double-nested post-frame callback to clear _isLoadingDocument ([#75](https://github.com/ScottKirvan/QuKi-Notes/issues/75) regression) ([28cff04](https://github.com/ScottKirvan/QuKi-Notes/commit/28cff04f2cc5e9d6bb29df11b6a3a7e9c0b4988d))
* **test:** assert format buttons disabled before super_editor sets initial cursor ([0c169c3](https://github.com/ScottKirvan/QuKi-Notes/commit/0c169c301b6fc8612c6cfecf499df99dfb384a06))
* **test:** remove unused formatting_toolbar import in toolbar test ([dbab625](https://github.com/ScottKirvan/QuKi-Notes/commit/dbab6253dca90baace4b4c9455a2ba42ffbb10ed))
* **test:** test format button disabled state after unfocus, not at cold launch ([6c44fa5](https://github.com/ScottKirvan/QuKi-Notes/commit/6c44fa585525bec8e17c7b70c52e5a93fdaf541d))
* **transports:** return empty list while settings loading to prevent flash (#post-96) ([1557281](https://github.com/ScottKirvan/QuKi-Notes/commit/15572811a95c85ceaf0fb872469be038478cc63f))

## [0.9.4](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.9.3...v0.9.4) (2026-06-10)


### Bug Fixes

* drop the status check and always return TossResult(success: true, ([8a52af6](https://github.com/ScottKirvan/QuKi-Notes/commit/8a52af6c1bb3f70e861112848fb43993b94a1b36))
* **editor:** correct two compile errors caught by CI ([d68a13e](https://github.com/ScottKirvan/QuKi-Notes/commit/d68a13e1cf8fa9f86da43617475c2488120bb2a3))
* **editor:** fix doc comment HTML lint warning in _hasQukisProvider ([14dd014](https://github.com/ScottKirvan/QuKi-Notes/commit/14dd0148ce427f16014da420dcf8650cfd46f687))
* **editor:** smart send fires direct when one transport enabled ([#85](https://github.com/ScottKirvan/QuKi-Notes/issues/85)) ([d9b7779](https://github.com/ScottKirvan/QuKi-Notes/commit/d9b77798c8d95ff6b8750ad2c33575af28cf2724))
* **toolbar:** replace code button with task list button; keyboard toggle ([#82](https://github.com/ScottKirvan/QuKi-Notes/issues/82), [#78](https://github.com/ScottKirvan/QuKi-Notes/issues/78)) ([a80fa45](https://github.com/ScottKirvan/QuKi-Notes/commit/a80fa454366cac43f6fbddef7fa0ef1c18233c4f))
* **transports:** ShareSheetToss always returns success — removes false-negative snackbar ([#92](https://github.com/ScottKirvan/QuKi-Notes/issues/92)) ([8a52af6](https://github.com/ScottKirvan/QuKi-Notes/commit/8a52af6c1bb3f70e861112848fb43993b94a1b36))

## [0.9.3](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.9.2...v0.9.3) (2026-06-09)


### Bug Fixes

* **editor:** resolve Logger ambiguity by hiding super_editor's Logger ([edaf04c](https://github.com/ScottKirvan/QuKi-Notes/commit/edaf04cf3968c39f2f1fc4a691e6553ee5a60de0))
* error handling, case-insensitive search, and stream utility extraction ([341e1bd](https://github.com/ScottKirvan/QuKi-Notes/commit/341e1bd328486d6c41acacfbcdca12746df4f836))
* force a release-please action ([ef33a04](https://github.com/ScottKirvan/QuKi-Notes/commit/ef33a048fea5628a1ae34823bfb99df960a6d53d))
* resolve ambiguous Logger import and add [@override](https://github.com/override) annotations ([ffff012](https://github.com/ScottKirvan/QuKi-Notes/commit/ffff012564fd346b4398175f1e115fd3002113e8))
* use show Logger, Level to resolve ambiguous import in editor_screen ([0b0d664](https://github.com/ScottKirvan/QuKi-Notes/commit/0b0d664c1212f87572b5de045e385584d21a77ca))

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
