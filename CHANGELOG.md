# Changelog

## [0.2.4](https://github.com/woodleighschool/woodsweep/compare/0.2.3...0.2.4) (2026-09-12)


### Continuous Integration

* avoid redundant release metadata checks ([f4f9e23](https://github.com/woodleighschool/woodsweep/commit/f4f9e23c17df61719be248d51d7f86045b8cb9d7))
* **github-action:** update action jdx/mise-action (v4.2.5 → v4.3.0) ([#25](https://github.com/woodleighschool/woodsweep/issues/25)) ([dbb4963](https://github.com/woodleighschool/woodsweep/commit/dbb4963557caee51932fb79557abc93956499250))


### Miscellaneous Chores

* fresh mise lock ([0093f41](https://github.com/woodleighschool/woodsweep/commit/0093f41ac94ab79de9902f99baef1a474169d2cc))
* **mise:** update mise tools ([#28](https://github.com/woodleighschool/woodsweep/issues/28)) ([17cb788](https://github.com/woodleighschool/woodsweep/commit/17cb7886ba0cb13d16de4db786d1e700de6a1cab))
* **mise:** update tool lefthook (2.1.11 → 2.1.12) ([#27](https://github.com/woodleighschool/woodsweep/issues/27)) ([454f523](https://github.com/woodleighschool/woodsweep/commit/454f523c53f5264bea64988c4c89b1b9153129b5))
* **mise:** update tool oxfmt (0.66.0 → 0.67.0) ([#29](https://github.com/woodleighschool/woodsweep/issues/29)) ([afdad60](https://github.com/woodleighschool/woodsweep/commit/afdad60051c164ef83f0f42614ed008617c43d87))
* **mise:** update tool zizmor (1.30.0 → 1.30.1) ([#30](https://github.com/woodleighschool/woodsweep/issues/30)) ([b7bd59f](https://github.com/woodleighschool/woodsweep/commit/b7bd59fee8432d1f0dfbe3ae5c1c34a9937b7fe9))
* remove redundant workflow lint task ([8fe0518](https://github.com/woodleighschool/woodsweep/commit/8fe0518096789a4549191bc1fab56dfa72732a93))

## [0.2.3](https://github.com/woodleighschool/woodsweep/compare/0.2.2...0.2.3) (2026-08-27)


### Bug Fixes

* **xcode:** xcode 26.3 min compatability ([228c77e](https://github.com/woodleighschool/woodsweep/commit/228c77e169d28a40137c817e1e6fc017618bb95a))


### Documentation

* clarify usage and releases ([b51682f](https://github.com/woodleighschool/woodsweep/commit/b51682fb843b4d4eee1de62d31b898441b8919af))


### Miscellaneous Chores

* **mise:** update tool oxfmt (0.64.0 → 0.65.0) ([#23](https://github.com/woodleighschool/woodsweep/issues/23)) ([7587500](https://github.com/woodleighschool/woodsweep/commit/7587500993cb26df900764d1c4d7ae13ec26ce1f))

## [0.2.2](https://github.com/woodleighschool/woodsweep/compare/0.2.1...0.2.2) (2026-08-24)


### Bug Fixes

* **ci:** pin released notarization action ([23d0187](https://github.com/woodleighschool/woodsweep/commit/23d0187938a7d84474aee4543bca17b534d25e10))
* use bundle ID for Keychain service ([de8b449](https://github.com/woodleighschool/woodsweep/commit/de8b449b1856c3ba07630caff725e918c82d4e96))


### Continuous Integration

* use apple notarize v2 ([365ca81](https://github.com/woodleighschool/woodsweep/commit/365ca817e1d265c303598caf0cdf7d6874951665))
* use shared notarization action ([9fb3218](https://github.com/woodleighschool/woodsweep/commit/9fb3218eb8fab49346e89b8355645dd8382a5e4d))

## [0.2.1](https://github.com/woodleighschool/woodsweep/compare/0.2.0...0.2.1) (2026-08-24)


### Bug Fixes

* provision the data protection keychain ([8979009](https://github.com/woodleighschool/woodsweep/commit/8979009ec2a8985a92a4e64d0923cc6443f2c7cf))
* **ui:** make failures terminal ([7039b0c](https://github.com/woodleighschool/woodsweep/commit/7039b0cfe36da05abe5eeb52bdc5519ffbf3bd46))
* use the data protection keychain ([6f68310](https://github.com/woodleighschool/woodsweep/commit/6f68310d225be52b8e52770fda8d846e6c0c2e27))


### Code Refactoring

* use SimpleKeychain for credentials ([7971a62](https://github.com/woodleighschool/woodsweep/commit/7971a621f247fc1a0fbf09624be88a0ba20a4c83))


### Documentation

* align repository agent guidance ([f07106c](https://github.com/woodleighschool/woodsweep/commit/f07106c5d53415a1ba853b484f1e41bd705c486f))
* clarify repository guidance ([ed67ee4](https://github.com/woodleighschool/woodsweep/commit/ed67ee40bdc909f8d2db57f6498e497640580933))


### Tests

* remove flaky process cancellation test ([b797e14](https://github.com/woodleighschool/woodsweep/commit/b797e142dab447cfb1ab4ea44b80c1aae566bb57))


### Build System

* share the macOS scheme ([946e0e8](https://github.com/woodleighschool/woodsweep/commit/946e0e862988049583bfe0fdd8d310b807494cc5))


### Continuous Integration

* add explicit app build checks ([40b81d9](https://github.com/woodleighschool/woodsweep/commit/40b81d9e93a03e5afae717ca442d735cf20af133))
* **github-action:** Update action home-operations/.github/actions/workflow-lint (v1.0.2 → v1.0.3) ([#14](https://github.com/woodleighschool/woodsweep/issues/14)) ([7830fac](https://github.com/woodleighschool/woodsweep/commit/7830fac7dbd3e227e759aa9f97442f4416cf3e5f))
* sync shared repository tooling ([ff67936](https://github.com/woodleighschool/woodsweep/commit/ff6793681b1da6a6069233120c26fd22cc97cfe5))
* verify the released app ([63f804b](https://github.com/woodleighschool/woodsweep/commit/63f804bbc1404a430a9e52b9733403a95e9574e2))


### Miscellaneous Chores

* align ignore rules ([647e5ea](https://github.com/woodleighschool/woodsweep/commit/647e5eaf0938b13b040febd1e6ee4194146d26d9))
* fix deployment target ([ea4554e](https://github.com/woodleighschool/woodsweep/commit/ea4554eb46cc2b925d6d12f4f6caec31896f3d2a))
* **mise:** update tool lefthook (2.1.10 → 2.1.11) ([#15](https://github.com/woodleighschool/woodsweep/issues/15)) ([d77889c](https://github.com/woodleighschool/woodsweep/commit/d77889cf2b0c78f6d55f58e6343ef099bc075a96))
* normalise icon ([25262c1](https://github.com/woodleighschool/woodsweep/commit/25262c1fa6327d0bac8b7ec8c3aab78ee1c27357))
* **release-please:** sync configuration ([7f1abbb](https://github.com/woodleighschool/woodsweep/commit/7f1abbb571c4d212f4d50e9ee3d55a4637afd7a5))
* remove redundant self-references ([f8edb30](https://github.com/woodleighschool/woodsweep/commit/f8edb30a18c9efee824280778562e7a5c03321c8))

## [0.2.0](https://github.com/woodleighschool/woodsweep/compare/0.1.4...0.2.0) (2026-08-20)


### ⚠ BREAKING CHANGES

* use Kopia Repository Server

### Features

* use Kopia Repository Server ([963f7cd](https://github.com/woodleighschool/woodsweep/commit/963f7cdbc7b92779fa01c679879f2c0aa779a673))


### Bug Fixes

* **ci:** disable automatic mise installs ([46339d5](https://github.com/woodleighschool/woodsweep/commit/46339d58fde2be1b29c879a3c08bf6b0e599c5b1))
* **ci:** switch to org-level secrets ([ca217e1](https://github.com/woodleighschool/woodsweep/commit/ca217e16c864bb3bb451b74b61e2152657ba97b9))
* **icon:** rename file, tweak position ([aa54541](https://github.com/woodleighschool/woodsweep/commit/aa54541e48cc5c1c3e0250a9197edfec93c4a7c2))

## [0.1.4](https://github.com/woodleighschool/woodsweep/compare/0.1.3...0.1.4) (2026-07-28)


### Bug Fixes

* **release:** distribute stapled app as ZIP ([29ab0f3](https://github.com/woodleighschool/woodsweep/commit/29ab0f3b02b67755381a5201e5a175548d91ffa5))

## [0.1.3](https://github.com/woodleighschool/woodsweep/compare/0.1.2...0.1.3) (2026-07-28)


### Bug Fixes

* **restart:** request macOS restart dialog ([edc3f23](https://github.com/woodleighschool/woodsweep/commit/edc3f2321259dc4b80245dcba82bd2186c0fe104))

## [0.1.2](https://github.com/woodleighschool/woodsweep/compare/0.1.1...0.1.2) (2026-07-28)


### Bug Fixes

* **release:** sign archives with Developer ID ([85d8cc3](https://github.com/woodleighschool/woodsweep/commit/85d8cc3c7259c81c9a7ed60ac6e4d5c0e0e88b11))

## [0.1.1](https://github.com/woodleighschool/woodsweep/compare/0.1.0...0.1.1) (2026-07-28)


### Features

* **backup:** connect and snapshot with Kopia ([e10a97f](https://github.com/woodleighschool/woodsweep/commit/e10a97f2cc00eab01de67719c71322c7e6467b49))
* **configuration:** store managed settings and secrets ([aa34e22](https://github.com/woodleighschool/woodsweep/commit/aa34e22f17945d35fec824826b1a53603c9ef1b0))
* **office:** request graceful application termination ([e1fa777](https://github.com/woodleighschool/woodsweep/commit/e1fa7771ab4f21a18624e4aa1afd119a48b4ac47))
* **office:** reset application user state ([43e0cef](https://github.com/woodleighschool/woodsweep/commit/43e0cefb677135e3712c9d87f7f35bdc072a703d))
* **reset:** constrain work to the target home ([b216279](https://github.com/woodleighschool/woodsweep/commit/b2162795663347e142a410efe1af03addf65417f))
* **reset:** gate cleanup on a successful snapshot ([2f83a9a](https://github.com/woodleighschool/woodsweep/commit/2f83a9ad0bb0489090a7b2bfc29f6a35186652a2))
* **reset:** reconcile the account home ([0b24513](https://github.com/woodleighschool/woodsweep/commit/0b245137b011f82da6589269bdccf869cb87b75a))
* **ui:** add the progressive reset flow ([095df93](https://github.com/woodleighschool/woodsweep/commit/095df93e6fdc00416851ad228c49bf62e1990693))


### Bug Fixes

* **account:** resolve configured user home ([de5c3a6](https://github.com/woodleighschool/woodsweep/commit/de5c3a641b75ea15af02522f3d8a7c5a5b86f253))
* **account:** use the current user home ([1ad7263](https://github.com/woodleighschool/woodsweep/commit/1ad726311c49c2dc564526e778867aaa489224dc))
* **backup:** constrain Kopia paths to target home ([6c175d4](https://github.com/woodleighschool/woodsweep/commit/6c175d4bf793822d6ec5ca948e64faf6f27f9b46))
* **build:** let Xcode sign Kopia ([05e7032](https://github.com/woodleighschool/woodsweep/commit/05e7032d35037f3ec86ad999e02699121ccd31a5))
* **configuration:** use data protection keychain ([1c8d24f](https://github.com/woodleighschool/woodsweep/commit/1c8d24f1aa35e0edc795a689008ffc5118121fd5))
* **configuration:** use the login keychain ([dcce758](https://github.com/woodleighschool/woodsweep/commit/dcce7585cc9e30485552fad4facce7733c6b33e4))
* enforce baseline command contracts ([2afe761](https://github.com/woodleighschool/woodsweep/commit/2afe761280f6e93080a9035e9827dac1fd47200b))
* **reset:** preserve the Public Drop Box ([05cba1d](https://github.com/woodleighschool/woodsweep/commit/05cba1d22cc4c2c4a3745b85cb114b5969b5be83))
* **reset:** serialize prerequisite startup ([7926805](https://github.com/woodleighschool/woodsweep/commit/79268056bc75ee93f698cd38db8bfc9858d43944))
* **xcode:** attach Kopia reference to project group ([c08459c](https://github.com/woodleighschool/woodsweep/commit/c08459cea6e4799414c3c2d4233ae4abf47a7eb7))


### Documentation

* **backup:** document global snapshot policy ([c3f8c9f](https://github.com/woodleighschool/woodsweep/commit/c3f8c9f0c0a8debfecc2755033d0294b62f4de08))
* correct the S3 endpoint example ([dd98ef4](https://github.com/woodleighschool/woodsweep/commit/dd98ef4f9041abe2172aee59a5667538b99948b3))

## Changelog
