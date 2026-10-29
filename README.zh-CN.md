# 复制绝对路径

简体中文 · [English](README.md)

只有一个功能：在 **Windows 11 文件资源管理器第一层右键菜单**添加 **“复制绝对路径”**。

右键文件或文件夹，即可复制不带引号的完整路径。多选时按选择顺序每行复制一条。菜单文字随 Windows 界面语言显示为中文或英文。

支持 **Windows 11 x64**。使用原生 C 实现的 `IExplorerCommand`，通过完整 MSIX 安装。运行时没有后台服务，也不访问网络。

## Tell your agent

把下面这段话直接发给你的 agent：

```text
请为我当前的 Windows 用户安装 https://github.com/hxxalpha/copy-absolute-path。
先阅读 README.zh-CN.md 和 scripts 下的脚本。使用 Windows 11 x64 的 64 位 PowerShell。
克隆仓库后，在仓库根目录依次执行：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sign.ps1 -Development
然后在同一个 Windows 账号的管理员 PowerShell 中执行安装；需要提权时发起 Windows UAC 确认：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install.ps1 -TrustCertificate
安装后验证：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1 -Registered -Clipboard
确认文件和文件夹的第一层右键菜单中有“复制绝对路径”。
最后告诉我安装版本，以及用 scripts\Uninstall.ps1 卸载的方法。
签名私钥保留在 Windows 证书存储中。本次任务只安装这个扩展。
```

## 构建与安装

克隆仓库，在目录中打开 **64 位 PowerShell**：

```powershell
git clone https://github.com/hxxalpha/copy-absolute-path.git
cd copy-absolute-path
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sign.ps1 -Development
```

构建脚本会从 TinyCC 官方发行站下载固定版本 0.9.27，并校验 SHA-256。签名脚本会从 NuGet 下载固定版本的微软 Windows SDK 签名工具，校验压缩包哈希和 SignTool 的微软签名。下载内容保存在 Git 忽略的 `.tools/` 目录中。C# 编译器使用 Windows 自带的 .NET Framework 4.x，无需安装 Visual Studio。

构建和签名的输出路径均为 `artifacts/CopyAbsolutePath-1.0.2.0-x64.msix`。签名时还会在旁边导出**公钥证书**；私钥不可导出，保留在当前用户的 Windows 证书存储中。

使用**同一个 Windows 账号**打开管理员 PowerShell，进入仓库目录，执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install.ps1 -TrustCertificate
```

`-TrustCertificate` 会将与安装包签名匹配的公钥证书导入本机的 **Trusted People（受信任人）**证书存储，用于安装本地自签名版本。菜单扩展只注册到当前用户。无需开启开发者模式，也不修改全局脚本执行策略。

安装后验证：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test.ps1 -Registered -Clipboard
```

现在右键文件或文件夹，选择 **“复制绝对路径”** 即可。如果资源管理器缓存了旧菜单，重启文件资源管理器后再试。

## 卸载

移除当前用户的菜单扩展：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall.ps1
```

如需同时删除本次构建导出的那张开发证书，在同一账号的管理员 PowerShell 中执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall.ps1 -RemoveCertificate
```

清理证书前请保留匹配的 `.cer` 文件。源码与构建产物保留在仓库目录中。

## 开发

- `src/CopyPathCommand.c`：原生菜单命令与剪贴板写入。
- `packaging/AppxManifest.xml`：Windows 11 第一层菜单注册。
- `tools/Pack.cs`：通过 Windows 打包 API 生成 MSIX。
- `tests/Verify.cs`：原生 COM、路径序列化、引用计数和可选剪贴板测试。
- `scripts/`：构建、测试、签名、安装与卸载。

普通测试不会修改剪贴板；指定 `-Clipboard` 会暂时修改剪贴板，并在结束后恢复原有内容。测试只使用合成文件。仓库在 `ci/windows.yml` 提供 Windows CI 模板，用于构建和测试未签名安装包；下载 CI 产物后仍需先签名才能安装。

已有编译器时，可传入 `Build.ps1 -TccRoot <包含 tcc.exe 的目录>`。签名支持 `Sign.ps1 -CertificateThumbprint <证书指纹>`，以及用 `-SignToolPath <signtool.exe>` 指定已安装的签名工具。正式签名证书需与 `project.json` 中的 `publisher` 一致。开发自签名用于本地构建；面向公众分发的正式版本应使用合适的受信任签名证书。

实现方式参考[微软的 Windows 11 菜单扩展文档](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer)。扩展 DLL 直接放入 MSIX，安装后不依赖源码所在目录。

## 许可证

[MIT](LICENSE)。构建工具许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
