# GameLog Release Guide

本文档描述从版本准备到 macOS 站外分发的流程。当前工程默认面向 Developer ID + 公证后的 ZIP 分发，不是 Mac App Store 沙箱版本。

## 发布前准备

1. 在 `Resources/Info.plist` 更新 `CFBundleShortVersionString` 和 `CFBundleVersion`。
2. 同步检查 `GameLog.xcodeproj/project.pbxproj` 中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
3. 更新 `CHANGELOG.md`、README 的功能范围和 `Docs/README.md` 的日期/阶段。
4. 确认第三方版本、SHA-256、许可文本和 `source.properties` 一致。
5. 用脱敏的真实设备流程完成 Android/iOS 最小验收。

## 本地验收构建

没有 Developer ID 证书时，可生成仅用于本机验证的 ad-hoc ZIP：

```bash
./script/package_release.sh
```

脚本会：

- 执行 Xcode Release Archive。
- 将 ADB、iOS 工具和动态库复制到 App Bundle。
- 按依赖顺序签名：iOS 动态库 → iOS 工具 → ADB → 外层 App。
- 生成 `dist/GameLog-<version>-macOS.zip`。
- 运行 `script/release_preflight.sh` 校验版本、架构、哈希、许可资源、归档和签名。

ad-hoc 产物不能作为对外发布版本，也不能替代公证。它只用于本机功能和 Bundle 完整性验收。

## Developer ID 发布

在已配置 Apple Developer 证书的机器上：

```bash
GAMELOG_SIGNING_IDENTITY="Developer ID Application: Your Team" \
./script/package_release.sh
```

该模式要求：

- Developer ID Application 证书在当前钥匙串中可用。
- 所有嵌套工具、动态库和外层 App 使用同一 Team ID 签名。
- Hardened Runtime、时间戳和严格签名检查通过。
- 公证前不把 App ZIP 上传到公共位置。

## 公证与 Gatekeeper

先在 `notarytool` 中创建并验证 Keychain profile，再运行：

```bash
GAMELOG_SIGNING_IDENTITY="Developer ID Application: Your Team" \
GAMELOG_NOTARY_PROFILE="gamelog-notary" \
./script/package_release.sh
```

脚本会提交 ZIP、等待公证、staple、验证 staple、运行 `spctl`，最后以 `GAMELOG_REQUIRE_DEVELOPER_ID=1` 和 `GAMELOG_REQUIRE_NOTARIZATION=1` 做严格预检。

不要在 shell 历史、CI 日志或仓库中记录公证 API key、私钥、Keychain profile 内容或证书文件。

## GitHub Release 清单

- [ ] Git tag 与 `CFBundleShortVersionString` 一致，例如 `v1.2.2`。
- [ ] `CHANGELOG.md` 已将版本从 Unreleased 移入正式日期段。
- [ ] `./script/package_release.sh` 成功。
- [ ] `GAMELOG_REQUIRE_DEVELOPER_ID=1 GAMELOG_REQUIRE_NOTARIZATION=1 ./script/release_preflight.sh` 成功。
- [ ] 在干净用户目录测试解压、首次启动、设备授权、截图和 Android 录屏。
- [ ] Release notes 说明 macOS 版本、Apple Silicon/Intel 边界、iOS 工具 arm64 限制和已知约束。
- [ ] 上传 ZIP 的 SHA-256，方便用户核验下载完整性。
- [ ] 不上传会话归档、真实日志、截图、录屏或签名材料。

## 第三方组件更新

更新 ADB 或 iOS 工具时，必须同时更新：

- 受管二进制和动态库。
- 来源版本、架构与 SHA-256。
- 上游 NOTICE/LICENSE 文本。
- `ThirdParty/ADB/README.md` 或 `ThirdParty/iOSDeviceTools/README.md`。
- App Bundle 中的第三方许可资源。

完成后运行 `script/release_preflight.sh` 并在 Apple Silicon 和 Intel（若仍兼容）上执行设备验收。详情见 [Third-Party Notices](Third-Party-Notices.md)。

