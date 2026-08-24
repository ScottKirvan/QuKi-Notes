# Changelog

## [0.24.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.23.0...v0.24.0) (2026-08-24)


### Features

* tap version number to copy it to clipboard ([6c45a1c](https://github.com/ScottKirvan/QuKi-Notes/commit/6c45a1c7c24eb6900068f57091eb869ffc3e7f7f))


### Bug Fixes

* dart format — collapse unnecessary line break in method chain ([0ba50f3](https://github.com/ScottKirvan/QuKi-Notes/commit/0ba50f389d4a7be5e61ecb50e3ec960bebcd7a9b))
* supply viewId to Windows TextInputConfiguration ([1cd392d](https://github.com/ScottKirvan/QuKi-Notes/commit/1cd392de9f95329c0a5417e289b09b44ceae63f6))

## [0.23.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.22.0...v0.23.0) (2026-08-16)


### Features

* extend list-toggle buttons to multi-line selections ([1cc4464](https://github.com/ScottKirvan/QuKi-Notes/commit/1cc4464c7f298206f35acb363485a8456a54fed4))
* strikethrough on checked checkbox text in rendered mode ([2788e54](https://github.com/ScottKirvan/QuKi-Notes/commit/2788e5469884f57aeadc6a8b3f9fc789301a8258))


### Bug Fixes

* checkbox toggle no longer scrolls the viewport ([d2958a6](https://github.com/ScottKirvan/QuKi-Notes/commit/d2958a643ec9692d101953208c71f1c9d2504bbb))
* deduplicate Discord notifications in notify.yml ([dfba6dc](https://github.com/ScottKirvan/QuKi-Notes/commit/dfba6dca16bce4949c7ddea83870ffd9e5afd12d))
* list-toggle buttons no longer corrupt heading lines on a collapsed selection ([7205cc3](https://github.com/ScottKirvan/QuKi-Notes/commit/7205cc3e90c30662f70f1eccb59408d3192802de))
* tighten icon-button spacing in toolbars and AppBars ([ea0214c](https://github.com/ScottKirvan/QuKi-Notes/commit/ea0214c5f9dc151f435fd287fd15eeeb7b681cf5))

## [0.22.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.21.1...v0.22.0) (2026-08-14)


### Features

* editor Trash button + snackbar Undo removal, shorter duration ([230e11b](https://github.com/ScottKirvan/QuKi-Notes/commit/230e11befd3e33ba4115cbad4e965bad8e209f7e))


### Bug Fixes

* add failing regression test for list-toggle-button unification ([d51f251](https://github.com/ScottKirvan/QuKi-Notes/commit/d51f2511e52a9890a4b7d35d6fc5c77f451da349))
* append version code to build name on manual dispatch only ([122f3ba](https://github.com/ScottKirvan/QuKi-Notes/commit/122f3ba15c6124724947451d46f4b0ccace36c27))
* mock SharedPreferences in editor_screen_test.dart to stop a full-suite-only flake ([5266881](https://github.com/ScottKirvan/QuKi-Notes/commit/52668813eb5bd9e55e7cfa28bfdae46add25a801))
* retry QuKiStorage.softDelete()'s rename on transient Windows file races ([a9f80dd](https://github.com/ScottKirvan/QuKi-Notes/commit/a9f80dd1354581dca6560f8ea089ad89eb18f0bb))
* rewrite delete-button tests to use fake storage, not real dart:io ([7f53dc8](https://github.com/ScottKirvan/QuKi-Notes/commit/7f53dc80d1db37c9486f012b8911beb94685a737))
* unify list-toggle-button detection across ul/ol/checkbox (ADR-34) ([dc22349](https://github.com/ScottKirvan/QuKi-Notes/commit/dc22349b89564723db701f4c1c068aef74206d3c))

Includes PRs: [#363](https://github.com/ScottKirvan/QuKi-Notes/pull/363), [#364](https://github.com/ScottKirvan/QuKi-Notes/pull/364), [#365](https://github.com/ScottKirvan/QuKi-Notes/pull/365), [#366](https://github.com/ScottKirvan/QuKi-Notes/pull/366), [#367](https://github.com/ScottKirvan/QuKi-Notes/pull/367), [#369](https://github.com/ScottKirvan/QuKi-Notes/pull/369), [#370](https://github.com/ScottKirvan/QuKi-Notes/pull/370), [#372](https://github.com/ScottKirvan/QuKi-Notes/pull/372)

## [0.21.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.21.0...v0.21.1) (2026-08-11)


### Bug Fixes

* add Play Store alpha/draft upload to Android build workflow ([bc0b9b8](https://github.com/ScottKirvan/QuKi-Notes/commit/bc0b9b82e2d28ffee80cbaf2ef5243e5c81fb9a1))
* add Play Store notes from staging and publish directly to alpha ([d876c98](https://github.com/ScottKirvan/QuKi-Notes/commit/d876c9810fd035bf6aaa64b1f00c3d3b2fa7d73c))
* read play-store-notes directly from staging branch ([a13aefc](https://github.com/ScottKirvan/QuKi-Notes/commit/a13aefc6a5ed59539a41c0e107f91d64119d8581))
* scope block-marker reveal to the marker itself, not the whole line ([#345](https://github.com/ScottKirvan/QuKi-Notes/issues/345), ADR-37) ([c03b4dd](https://github.com/ScottKirvan/QuKi-Notes/commit/c03b4ddcd6cdff9238187a31ee54ed1a52556fb7))
* set versionCode to yydddHHMM timestamp at build time ([26f3583](https://github.com/ScottKirvan/QuKi-Notes/commit/26f35834f3098ae095192fbcfa66d6d32942a746))

## [0.21.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.20.0...v0.21.0) (2026-08-10)


### Features

* add pre-release staging workflow, update release pipeline ([caf0888](https://github.com/ScottKirvan/QuKi-Notes/commit/caf0888a2e7ab5206cedc9a9db9ec9ab91bbbedc))
* auto-scroll while dragging a selection handle near a viewport edge ([063bc45](https://github.com/ScottKirvan/QuKi-Notes/commit/063bc456511dec9cbc285ec333ef45e35e69101a))
* convert pasted HTML clipboard content to GFM markdown (ADR-35) ([04c0a6a](https://github.com/ScottKirvan/QuKi-Notes/commit/04c0a6a680a5744b0db87903022d9a8f8498e88d))
* draggable selection handles (ADR-36 Stage 2) ([3a4ec5d](https://github.com/ScottKirvan/QuKi-Notes/commit/3a4ec5de315af96bb3911fea909d0077de2e41c2))
* entity-aware double-tap selection, fix long-press word truncation ([3526a92](https://github.com/ScottKirvan/QuKi-Notes/commit/3526a92056a2b8d9c1e7f0f70e8b9cf4cf7b8729))
* interactive Indent/Dedent for list items and paragraphs (ADR-34 Stage 4, [#77](https://github.com/ScottKirvan/QuKi-Notes/issues/77)) ([993a7fc](https://github.com/ScottKirvan/QuKi-Notes/commit/993a7fcbb6952bc0c6798cc0e496118d3cffac86))
* selection handle magnifier + haptic feedback (ADR-36 Stage 4) ([5945278](https://github.com/ScottKirvan/QuKi-Notes/commit/5945278fad91f361e92fe0df322e82f8e8f41c73))


### Bug Fixes

* add manual workflow dispatch for rewriting release notes ([61b2a1f](https://github.com/ScottKirvan/QuKi-Notes/commit/61b2a1f3f08f07b576a76fdf054eaf6a8c8a5649))
* anchor checkbox tap zone at the row's true left edge, not the gutter width ([#352](https://github.com/ScottKirvan/QuKi-Notes/issues/352), round 2) ([86abf1a](https://github.com/ScottKirvan/QuKi-Notes/commit/86abf1a13b7d5e2de1c7d9be18736f7489bb082f))
* correct selection-handle touch resolution for its below-line offset ([189d35a](https://github.com/ScottKirvan/QuKi-Notes/commit/189d35ad6de78b9abcf2bf22bbe42eade1824bf1))
* extend checkbox tap hit-test zone to cover content padding ([#352](https://github.com/ScottKirvan/QuKi-Notes/issues/352), round 4) ([cb39711](https://github.com/ScottKirvan/QuKi-Notes/commit/cb397110b18872b04595846fb3093abf9b25779c))
* hr lines no-op on Indent — no tab position preserves recognition ([c164630](https://github.com/ScottKirvan/QuKi-Notes/commit/c164630fdaffd36ea77d0f8c275dcc08b381a252))
* keep checkbox taps and text selection reading-mode-safe ([#335](https://github.com/ScottKirvan/QuKi-Notes/issues/335), [#266](https://github.com/ScottKirvan/QuKi-Notes/issues/266), [#336](https://github.com/ScottKirvan/QuKi-Notes/issues/336)) ([a9c3219](https://github.com/ScottKirvan/QuKi-Notes/commit/a9c3219f7b69785d8d0b276cbb06dbd96c53a577))
* make FormattingToolbar horizontally scrollable ([75fdd89](https://github.com/ScottKirvan/QuKi-Notes/commit/75fdd89a932df014ad467ace3db143eababc4a5e))
* migrate starline badge to self-hosted GitHub Action ([228e5bf](https://github.com/ScottKirvan/QuKi-Notes/commit/228e5bf27fd6f063b7e5ecf9c45648a809f03dff))
* move link banner to header and add Ko-Fi support link ([fd6d4a3](https://github.com/ScottKirvan/QuKi-Notes/commit/fd6d4a34078af9c91510a0aef77e248c7c37e400))
* selection handle overlay position going stale after scrolling ([a1986b4](https://github.com/ScottKirvan/QuKi-Notes/commit/a1986b46f51f97a813ed55d48b0faedbdfb40bcb))
* skip leading indentation whitespace before reading a checkbox's marker ([#354](https://github.com/ScottKirvan/QuKi-Notes/issues/354)) ([2b1d21f](https://github.com/ScottKirvan/QuKi-Notes/commit/2b1d21f7228eaf2c70349ac8b03cea3bc6c96a93))
* strip non-functional cold-launch auto-focus; correct docs claiming it and image rendering work ([6ee0db9](https://github.com/ScottKirvan/QuKi-Notes/commit/6ee0db92fe493f27636c7f8cadaf077ec65fe1d1))
* swap super_clipboard for quill_native_bridge in HTML paste (ADR-35) ([1ca9745](https://github.com/ScottKirvan/QuKi-Notes/commit/1ca974554b731611e267e0e9546a2c8222c723ef))
* **ui:** add Ko-fi link, QuKis list Help button, tighter list density ([5dbe834](https://github.com/ScottKirvan/QuKi-Notes/commit/5dbe834faa4c03618963b24345ebe9557b851adb))
* widen checkbox tap hit-test zone beyond the exact painted glyph ([#352](https://github.com/ScottKirvan/QuKi-Notes/issues/352)) ([c1a8d44](https://github.com/ScottKirvan/QuKi-Notes/commit/c1a8d44a83a65325c418b8fdb67008f3cfb6a7f8))
* widen literal tab rendering to 4 space-widths ([#305](https://github.com/ScottKirvan/QuKi-Notes/issues/305) follow-up) ([7a77b39](https://github.com/ScottKirvan/QuKi-Notes/commit/7a77b39324e2e6a3d9bb391d9a8337409b2c3b72))
* wire discord_blurb through artifact, update context, add preview workflow ([177b03b](https://github.com/ScottKirvan/QuKi-Notes/commit/177b03bf37aff8713a3110c7088461b636c2fb6b))

## [0.20.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.19.0...v0.20.0) (2026-07-24)


### Features

* **editor:** multi-run block indentation, nested blockquotes (ADR-34 Stage 1) ([86d56d5](https://github.com/ScottKirvan/QuKi-Notes/commit/86d56d595896bb5af2de92441e5a63b53045a7d4))
* **editor:** nested list indentation, wired into multi-run rendering (ADR-34 Stage 2+3) ([aa3c0d5](https://github.com/ScottKirvan/QuKi-Notes/commit/aa3c0d5de119a2d52cddac9dfccd3f2691fc822b))


### Bug Fixes

* **editor:** blockquote content indent + stripe vertical alignment ([423ea52](https://github.com/ScottKirvan/QuKi-Notes/commit/423ea5288aed3b3d21047c5f8ac33bdaf2cf1a01))
* **editor:** blockquote rendering bugs (Stage 4 addendum) ([0f5ff75](https://github.com/ScottKirvan/QuKi-Notes/commit/0f5ff752d8d0f50fd13813065baa4d7d7d02bd83))
* **editor:** marker gutter leak, Tab keystroke swallowed, list marker vertical alignment ([02ee02e](https://github.com/ScottKirvan/QuKi-Notes/commit/02ee02ecbdc1e2c5296266f789530397c391e463))
* **editor:** nested and combined inline markdown (Stage 1 — paragraphs & headings) ([a52fd6c](https://github.com/ScottKirvan/QuKi-Notes/commit/a52fd6cff768da39a4fcf58d1b6988f4b9b6cd96))
* **editor:** nested and combined inline markdown (Stage 2 — list items) ([5c150f7](https://github.com/ScottKirvan/QuKi-Notes/commit/5c150f754e6b70be2fd3204769fd9923979b0099))
* **editor:** nested and combined inline markdown (Stage 4 — blockquotes) ([c042bae](https://github.com/ScottKirvan/QuKi-Notes/commit/c042baeca457820c9d003ca89832ff79985a306f))
* **editor:** ol numbering across deeper interruption + list marker gutter alignment ([8ec5a7d](https://github.com/ScottKirvan/QuKi-Notes/commit/8ec5a7ddadedfa688028c3a92947a8da18e2bd4a))
* **editor:** scan nested emphasis inside link text ([bb20ea2](https://github.com/ScottKirvan/QuKi-Notes/commit/bb20ea28676b2d8fccaf608e966571dced5e3ff9))
* **editor:** single-line HTML detection (Stage 3) ([b07c7eb](https://github.com/ScottKirvan/QuKi-Notes/commit/b07c7eb06dd31e9ee6f0f7e53c5f9bd3e746cec6))

Includes PRs: [#275](https://github.com/ScottKirvan/QuKi-Notes/pull/275), [#276](https://github.com/ScottKirvan/QuKi-Notes/pull/276), [#277](https://github.com/ScottKirvan/QuKi-Notes/pull/277), [#278](https://github.com/ScottKirvan/QuKi-Notes/pull/278), [#279](https://github.com/ScottKirvan/QuKi-Notes/pull/279), [#280](https://github.com/ScottKirvan/QuKi-Notes/pull/280), [#281](https://github.com/ScottKirvan/QuKi-Notes/pull/281), [#282](https://github.com/ScottKirvan/QuKi-Notes/pull/282), [#283](https://github.com/ScottKirvan/QuKi-Notes/pull/283), [#284](https://github.com/ScottKirvan/QuKi-Notes/pull/284), [#286](https://github.com/ScottKirvan/QuKi-Notes/pull/286), [#287](https://github.com/ScottKirvan/QuKi-Notes/pull/287), [#288](https://github.com/ScottKirvan/QuKi-Notes/pull/288), [#289](https://github.com/ScottKirvan/QuKi-Notes/pull/289), [#290](https://github.com/ScottKirvan/QuKi-Notes/pull/290), [#291](https://github.com/ScottKirvan/QuKi-Notes/pull/291), [#292](https://github.com/ScottKirvan/QuKi-Notes/pull/292), [#293](https://github.com/ScottKirvan/QuKi-Notes/pull/293), [#294](https://github.com/ScottKirvan/QuKi-Notes/pull/294), [#295](https://github.com/ScottKirvan/QuKi-Notes/pull/295), [#296](https://github.com/ScottKirvan/QuKi-Notes/pull/296)

## [0.19.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.18.2...v0.19.0) (2026-07-21)


### Features

* **editor:** Send+Settings icon buttons, sticky plaintext mode ([#249](https://github.com/ScottKirvan/QuKi-Notes/issues/249), [#251](https://github.com/ScottKirvan/QuKi-Notes/issues/251)) ([fd889fc](https://github.com/ScottKirvan/QuKi-Notes/commit/fd889fc21781ff7a4c2b71fab7016b555eb9b94d))
* **settings:** help/about dialog — docs, Discord, GitHub ([#253](https://github.com/ScottKirvan/QuKi-Notes/issues/253)) ([03eb986](https://github.com/ScottKirvan/QuKi-Notes/commit/03eb986e03f2443466bfd26a146588894ec42b0f))
* **settings:** help/about dialog ([#253](https://github.com/ScottKirvan/QuKi-Notes/issues/253)) ([5ac96d2](https://github.com/ScottKirvan/QuKi-Notes/commit/5ac96d24b2c6d05907c025ffb30a199bd7302f90))


### Bug Fixes

* **android:** set launchMode singleTask to prevent new instance on share-in ([#188](https://github.com/ScottKirvan/QuKi-Notes/issues/188)) ([448e775](https://github.com/ScottKirvan/QuKi-Notes/commit/448e7759cd25da69eb841017b3a989b5eed62dcb))
* **editor:** dart format md_parser_test.dart ([f34fe99](https://github.com/ScottKirvan/QuKi-Notes/commit/f34fe990f2209c2977353da1a5b6a53b8d7d579f))
* **editor:** force text presentation on checkbox glyphs ([#267](https://github.com/ScottKirvan/QuKi-Notes/issues/267)) ([baf617d](https://github.com/ScottKirvan/QuKi-Notes/commit/baf617d8ad2ccb06784005a94ac62fc47f200c1f))
* **editor:** markdown mark CustomPainter for edit+rendered T button icon ([#239](https://github.com/ScottKirvan/QuKi-Notes/issues/239)) ([34224db](https://github.com/ScottKirvan/QuKi-Notes/commit/34224db358895fef67cab0f04677e3697c59026c))
* **editor:** paint checkbox glyphs via Canvas instead of Unicode text ([#267](https://github.com/ScottKirvan/QuKi-Notes/issues/267)) ([1dedc6c](https://github.com/ScottKirvan/QuKi-Notes/commit/1dedc6c93a42e8c0505f739a9f746e239b70ac81))
* **editor:** reading mode, toolbar gating, wrapSelection cursor, bottom padding ([#234](https://github.com/ScottKirvan/QuKi-Notes/issues/234), [#235](https://github.com/ScottKirvan/QuKi-Notes/issues/235), [#236](https://github.com/ScottKirvan/QuKi-Notes/issues/236), [#239](https://github.com/ScottKirvan/QuKi-Notes/issues/239)) ([97e026d](https://github.com/ScottKirvan/QuKi-Notes/commit/97e026d479702394e0a5fec1375100d17eca08ff))
* **editor:** size checkbox box off measured reserved width, not line height ([aa507fe](https://github.com/ScottKirvan/QuKi-Notes/commit/aa507fe09aa37b9c7a7ee15ea76e2bfbd1ccdd4e))
* **editor:** stop shrinking checkbox tap target to fit reserved gap ([c4412e7](https://github.com/ScottKirvan/QuKi-Notes/commit/c4412e7871af2f34050ec173971c80d4fe9b688e))
* **editor:** tune canvas checkbox glyph size, position, and text gap ([94536bd](https://github.com/ScottKirvan/QuKi-Notes/commit/94536bdd40df5c8eef102c7c6613ca7b451cfdbd))
* **editor:** use geometric square glyphs for checkboxes instead of emoji ([#267](https://github.com/ScottKirvan/QuKi-Notes/issues/267)) ([98c95f5](https://github.com/ScottKirvan/QuKi-Notes/commit/98c95f5624082a4e7785d951755249b9c4ad3822))
* **settings:** add contrasting border to help dialog ([dea553c](https://github.com/ScottKirvan/QuKi-Notes/commit/dea553cc3cb1ab00f4f0d272790ca8eb9b60bb86))
* **settings:** help dialog link buttons and dark modal bg ([a8b5f69](https://github.com/ScottKirvan/QuKi-Notes/commit/a8b5f69246065206cac98b542ba4c614e31e7a49))


### Reverts

* undo solid-square checkbox glyphs ([#267](https://github.com/ScottKirvan/QuKi-Notes/issues/267)) ([dffa792](https://github.com/ScottKirvan/QuKi-Notes/commit/dffa792f68e48419b58eb48dc949fc3253bed98e))

Includes PRs: [#233](https://github.com/ScottKirvan/QuKi-Notes/pull/233), [#257](https://github.com/ScottKirvan/QuKi-Notes/pull/257), [#258](https://github.com/ScottKirvan/QuKi-Notes/pull/258), [#259](https://github.com/ScottKirvan/QuKi-Notes/pull/259), [#260](https://github.com/ScottKirvan/QuKi-Notes/pull/260), [#262](https://github.com/ScottKirvan/QuKi-Notes/pull/262), [#270](https://github.com/ScottKirvan/QuKi-Notes/pull/270), [#271](https://github.com/ScottKirvan/QuKi-Notes/pull/271), [#273](https://github.com/ScottKirvan/QuKi-Notes/pull/273), [#274](https://github.com/ScottKirvan/QuKi-Notes/pull/274)

## [0.18.2](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.18.1...v0.18.2) (2026-07-12)


### Bug Fixes

* dart format - CI / build breaker ([2afb9b1](https://github.com/ScottKirvan/QuKi-Notes/commit/2afb9b1d6b2cd526c6e5a28af85e22955694fd9d))
* **editor:** focus editor on launch via postFrameCallback — fixes keyboard on Windows/Linux ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([923cec2](https://github.com/ScottKirvan/QuKi-Notes/commit/923cec2d7cf2d04467ad485137462500e8de1bd6))
* text fixup "toss" -&gt; "send" ([f963cc0](https://github.com/ScottKirvan/QuKi-Notes/commit/f963cc0198d2dce0c1e33e58b66ae1d606b7ef94))

Includes PRs: [#227](https://github.com/ScottKirvan/QuKi-Notes/pull/227), [#228](https://github.com/ScottKirvan/QuKi-Notes/pull/228), [#229](https://github.com/ScottKirvan/QuKi-Notes/pull/229), [#230](https://github.com/ScottKirvan/QuKi-Notes/pull/230), [#231](https://github.com/ScottKirvan/QuKi-Notes/pull/231), [#232](https://github.com/ScottKirvan/QuKi-Notes/pull/232)

## [0.18.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.18.0...v0.18.1) (2026-07-08)


### Bug Fixes

* **editor:** tap collapsed checkbox glyph to toggle - [ ] / - [x] ([#130](https://github.com/ScottKirvan/QuKi-Notes/issues/130)) ([a36fa0f](https://github.com/ScottKirvan/QuKi-Notes/commit/a36fa0f600fc151952a58948de26291399709736))
* **storage:** skip sidecar write when file missing or corrupt ([#75](https://github.com/ScottKirvan/QuKi-Notes/issues/75)) ([8a91004](https://github.com/ScottKirvan/QuKi-Notes/commit/8a9100400bf9d5cecbcfbcda472c78c3a52121f0))
* **storage:** store modifiedAt in sidecar JSON to decouple sort from filesystem mtime ([#75](https://github.com/ScottKirvan/QuKi-Notes/issues/75)) ([4fff805](https://github.com/ScottKirvan/QuKi-Notes/commit/4fff805445e8e19521d6483d794b39b6d873c7a3))

Includes PRs: [#223](https://github.com/ScottKirvan/QuKi-Notes/pull/223), [#224](https://github.com/ScottKirvan/QuKi-Notes/pull/224), [#225](https://github.com/ScottKirvan/QuKi-Notes/pull/225), [#226](https://github.com/ScottKirvan/QuKi-Notes/pull/226)

## [0.18.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.17.0...v0.18.0) (2026-07-07)


### Features

* **editor:** blockquotes, horizontal rules, autolink word-boundary, inline code bg fix ([15f5353](https://github.com/ScottKirvan/QuKi-Notes/commit/15f5353cb84389d8b17ce1135ce7fde8d4510229))


### Bug Fixes

* **parser:** GFM inline markup batch — strikethrough, inlineCode, h4-h6, autolinks; icon + color fixes ([f45dc10](https://github.com/ScottKirvan/QuKi-Notes/commit/f45dc10a2e9dafbe9f904bd290d528cc368c9172))
* **parser:** skip both chars of unmatched '**'/'__' to prevent spurious italic ([b7d8b71](https://github.com/ScottKirvan/QuKi-Notes/commit/b7d8b71b2fea2e976a079b3a66e01759a50ae317)), closes [#219](https://github.com/ScottKirvan/QuKi-Notes/issues/219)

Includes PRs: [#220](https://github.com/ScottKirvan/QuKi-Notes/pull/220), [#221](https://github.com/ScottKirvan/QuKi-Notes/pull/221), [#222](https://github.com/ScottKirvan/QuKi-Notes/pull/222)

## [0.17.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.16.1...v0.17.0) (2026-07-07)


### Features

* **editor:** implement selection toolbar for mobile (ADR-31) ([d5deca4](https://github.com/ScottKirvan/QuKi-Notes/commit/d5deca473cd0d39dfb3a21aeb087bd5c37e1a20c))
* **markdown_live_editor:** ADR-31 Stage 2 — parser + reveal/collapse for headings, bold, italic ([f5888dc](https://github.com/ScottKirvan/QuKi-Notes/commit/f5888dc36215e1994755e20c66489546a4b8bb6f))
* **markdown_live_editor:** ADR-31 Stage 4 — list glyphs, checkboxes, ordered-list numbering ([fc3fed3](https://github.com/ScottKirvan/QuKi-Notes/commit/fc3fed39d30292b4e5d5dbeed9d3e3ef85b5a66a))
* **markdown_live_editor:** ADR-31 Stage 5 — block-level inline images ([1645ee7](https://github.com/ScottKirvan/QuKi-Notes/commit/1645ee74155f9a2d52f9bc0ea9858579c3f48398))
* **markdown_live_editor:** ADR-31 Stage 6 — inline link rendering and tap-to-navigate ([eb8114b](https://github.com/ScottKirvan/QuKi-Notes/commit/eb8114ba868c64a706c276824ad904f8be3296f2))


### Bug Fixes

* **editor:** show toolbar on collapsed selection; re-show after Select All ([a8b926c](https://github.com/ScottKirvan/QuKi-Notes/commit/a8b926cdab691f9b1430050fdea4b65814bf7e64))
* extend CI format check and tests to cover packages/markdown_live_editor ([62e1bcc](https://github.com/ScottKirvan/QuKi-Notes/commit/62e1bccefe95dded60c6c8162a94c3bbf347118b))
* **markdown_live_editor:** ADR-31 Stage 2 — reveal at element.end + delimiter color ([0acbfe5](https://github.com/ScottKirvan/QuKi-Notes/commit/0acbfe5cecd66f07d02f683a31d478a238d488d0))
* **markdown_live_editor:** image cache — replace map on update so render object detects change ([625a5fa](https://github.com/ScottKirvan/QuKi-Notes/commit/625a5fa9456621564368fe44df1655b30764a098))
* **markdown_live_editor:** list auto-continue IME sync, ol source numbering, plain text mode ([e14c4f3](https://github.com/ScottKirvan/QuKi-Notes/commit/e14c4f314bb1bbd76d26f50b1e4d6e73bf56be0f))
* **markdown_live_editor:** ol block-relative seqNum (GFM-compatible) ([2c29257](https://github.com/ScottKirvan/QuKi-Notes/commit/2c292577262752e0917a1e5f6b7b74fadfd0d336))
* upload APK as artifact when triggered via workflow_dispatch ([1d38f7d](https://github.com/ScottKirvan/QuKi-Notes/commit/1d38f7d547370643417a82180e406be8e5538001))
* upload build artifacts on workflow_dispatch for Windows, Linux, iOS ([e252bb6](https://github.com/ScottKirvan/QuKi-Notes/commit/e252bb6fe6f017c6d65dd9bd043b79e64a927308))

Includes PRs: [#205](https://github.com/ScottKirvan/QuKi-Notes/pull/205), [#206](https://github.com/ScottKirvan/QuKi-Notes/pull/206), [#207](https://github.com/ScottKirvan/QuKi-Notes/pull/207), [#208](https://github.com/ScottKirvan/QuKi-Notes/pull/208), [#209](https://github.com/ScottKirvan/QuKi-Notes/pull/209), [#210](https://github.com/ScottKirvan/QuKi-Notes/pull/210), [#211](https://github.com/ScottKirvan/QuKi-Notes/pull/211), [#212](https://github.com/ScottKirvan/QuKi-Notes/pull/212), [#213](https://github.com/ScottKirvan/QuKi-Notes/pull/213), [#214](https://github.com/ScottKirvan/QuKi-Notes/pull/214), [#215](https://github.com/ScottKirvan/QuKi-Notes/pull/215), [#216](https://github.com/ScottKirvan/QuKi-Notes/pull/216), [#217](https://github.com/ScottKirvan/QuKi-Notes/pull/217), [#218](https://github.com/ScottKirvan/QuKi-Notes/pull/218)

## [0.16.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.16.0...v0.16.1) (2026-07-05)


### Bug Fixes

* **editor:** gesture handling, keyboard lifecycle, scroll hit-test, long-press selection ([059f979](https://github.com/ScottKirvan/QuKi-Notes/commit/059f979c6cc5e2f36dc540727e0d49c00e11f926))

Includes PRs: [#203](https://github.com/ScottKirvan/QuKi-Notes/pull/203), [#204](https://github.com/ScottKirvan/QuKi-Notes/pull/204)

## [0.16.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.15.3...v0.16.0) (2026-07-05)


### Features

* **editor:** ADR-31 Stage 1 — custom RenderObject + TextInputClient plain-text editor ([0fdddf8](https://github.com/ScottKirvan/QuKi-Notes/commit/0fdddf851f0689ef82a075319e42ee738a06688f))


### Bug Fixes

* **editor:** theme cursor/selection colors; [@visible](https://github.com/visible)ForTesting on setSelectionForTesting ([387bd33](https://github.com/ScottKirvan/QuKi-Notes/commit/387bd335046b453c99ea7e9163f823e9bd96eb93))

Includes PRs: [#200](https://github.com/ScottKirvan/QuKi-Notes/pull/200), [#201](https://github.com/ScottKirvan/QuKi-Notes/pull/201), [#202](https://github.com/ScottKirvan/QuKi-Notes/pull/202)

## [0.15.3](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.15.2...v0.15.3) (2026-07-03)

### Pull Requests

* [#197](https://github.com/ScottKirvan/QuKi-Notes/pull/197) chore(main): release 0.15.3



### Bug Fixes

* force a build ([3ce697f](https://github.com/ScottKirvan/QuKi-Notes/commit/3ce697f138174f4d090baf090cb378ac9f294e7f))

## [0.15.2](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.15.1...v0.15.2) (2026-07-03)


### Bug Fixes

* add workflow_dispatch to release workflow ([dcba9da](https://github.com/ScottKirvan/QuKi-Notes/commit/dcba9da5ddc72bb94beaa57d86b485e3698c407c))
* clean up root CHANGELOG.md and add PR link job ([a820b7f](https://github.com/ScottKirvan/QuKi-Notes/commit/a820b7fbe8d443596b9a7ede6dff9b68f4f2bb86))
* **markdown_live_editor:** list bullets, checkbox visibility, toolbar selection ([1f421c7](https://github.com/ScottKirvan/QuKi-Notes/commit/1f421c7b990212547c9b9a6c8a3b74ad9f9dcead))

## [0.15.1](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.15.0...v0.15.1) (2026-07-03)


### Bug Fixes

* **editor:** zero-width hidden syntax chars to remove spacing around styled text ([76fa3bc](https://github.com/ScottKirvan/QuKi-Notes/commit/76fa3bce06dfa0194cb59bd099dda59cdae17b99))

## [0.15.0](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.11...v0.15.0) (2026-07-03)


### Features

* **editor:** replace block-flip with single-buffer TextSpan editor (ADR-30) ([ca3d031](https://github.com/ScottKirvan/QuKi-Notes/commit/ca3d0313f5e1b96216005b3795466d1cc3cd426a))

## [0.14.11](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.10...v0.14.11) (2026-06-30)


### Bug Fixes

* **editor:** remove unused _activateLastBlock ([8f13735](https://github.com/ScottKirvan/QuKi-Notes/commit/8f137354b5dae6a7095106f41ce0b7f372bb6850))
* **editor:** tapping below note places cursor at end of last block ([51c0ff6](https://github.com/ScottKirvan/QuKi-Notes/commit/51c0ff6afdbfdc1745822663a2099955eae041b1))

## [0.14.10](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.9...v0.14.10) (2026-06-30)


### Bug Fixes

* add emoji input to discord-notify job ([5b0cbe9](https://github.com/ScottKirvan/QuKi-Notes/commit/5b0cbe934dc71aa675b1529b36d57de877d77c5c))
* **editor:** also open keyboard when tapping + from an existing QuKi ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([6803485](https://github.com/ScottKirvan/QuKi-Notes/commit/68034854d7d687cc0022c48e47e38b8fa48c0aa1))

## [0.14.9](https://github.com/ScottKirvan/QuKi-Notes/compare/v0.14.8...v0.14.9) (2026-06-30)


### Bug Fixes

* **editor:** open keyboard when tapping + on a blank note ([#72](https://github.com/ScottKirvan/QuKi-Notes/issues/72)) ([6074162](https://github.com/ScottKirvan/QuKi-Notes/commit/60741626fa96c1df5c408ad8aaab30aa1efa3d0b))

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
