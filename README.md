<p align="center">
  <img src="Assets/LinguaLogo.png" width="96" alt="Lingua icon">
</p>

# Lingua for Mac

**English** | [简体中文](README.zh-CN.md)

A native macOS AI translation workspace for text translation, image OCR, and reviewing translations in one window. Built with SwiftUI, Apple Vision, and MLX Swift, with local inference on your Mac.

**[Download on the Mac App Store](https://apps.apple.com/app/id6823065438)** · [Report an issue](https://github.com/xingj404-lab/Lingua/issues) · [Contribute](CONTRIBUTING.md) · [MIT License](LICENSE)

## Features

- **On-device AI translation**: supported Hy-MT2 and Qwen models, streaming output, cancellation, model downloads, and model switching.
- **Screenshot and image OCR**: paste screenshots, drag images into the workspace, or import files. Extract text with Apple Vision and review it before translating.
- **Side-by-side editing**: edit both source and translated text, choose a subject area and style, add terminology hints, and check for potentially missing numbers or terms.
- **Local workspace**: the latest 100 translation records, search, a glossary, TXT / Markdown import, and TXT export.
- **Optional API services**: connect to an OpenAI-compatible HTTPS endpoint or a local loopback service.
- **Multilingual interface**: Simplified Chinese, English, Japanese, and Korean, with system light and dark appearance.

## Download and get started

Install from the **[Mac App Store](https://apps.apple.com/app/id6823065438)**. The listing is named **Lingua: Offline AI Translator**.

1. Enter text, or paste or drag in an image for OCR.
2. Choose a local model in Settings, then select the target language and translation options.
3. Translate, review, edit, copy, or export the result.

The App Store version includes a default model for offline translation in local mode. Additional models must be downloaded first; API mode requires your own service configuration.

## Privacy and data

| Activity | Where data goes |
| --- | --- |
| Image OCR and local model translation | Processed on your Mac |
| Translation history and glossary | Stored locally, with no cloud sync |
| Additional model downloads | Connects to your selected Hugging Face, HF-Mirror, or custom HTTPS download source |
| Optional API translation | Sends source text and relevant glossary terms to your configured service after authorization |

Lingua does not automatically fall back to a remote API if local inference fails. API sending permissions are stored per service address and can be revoked. The service provider determines its own data retention practices.

API keys are session-only by default. If you choose to save a key, it is stored in a local plaintext JSON file in the app data directory, with directory permissions of `0700` and file permissions of `0600`. It is not stored in macOS Keychain. Do not include credentials or real translation records in issues.

See the in-app privacy policy or the [English privacy policy source](Sources/LinguaMac/Resources/Legal/privacy-en.md) for details.

## Build from source

### Requirements

- An Apple Silicon Mac running macOS 14 or later.
- A full Xcode toolchain supporting Swift 6.2 or later.
- Python 3 for packaging scripts and some tests; it is not an app runtime dependency.
- Internet access for initial Swift Package resolution. Dependency versions are pinned in `Package.resolved`.

```sh
git clone https://github.com/xingj404-lab/Lingua.git
cd Lingua
cp Distribution/Config/Local.xcconfig.example Distribution/Config/Local.xcconfig
open Lingua.xcodeproj
```

In Xcode, select the **Lingua** scheme and **My Mac**, and configure your own development team.

**Model weights are not included in this source repository.** The full app build currently bundles the default Hy-MT2 model. Prepare a verified snapshot containing `.lingua-manifest.json` and all model files, then point `LINGUA_DEFAULT_MODEL_DIR` to that directory. The packaging script reads local files only; it does not download weights automatically.

To archive after preparing the model and signing configuration:

```sh
LINGUA_DEFAULT_MODEL_DIR="/absolute/path/to/verified-model-snapshot" ./scripts/archive-app.sh
```

A full MLX build requires Xcode / `xcodebuild` to compile Metal shaders; `swift build` alone is insufficient. See the [release and build guide](docs/release/README.md) (Chinese) for model preparation, sandboxing, signing, and archiving. That guide retains initial release preparation notes; check the App Store for current distribution status.

### Checks and tests

```sh
./scripts/check.sh
```

This script builds a check package without the MLX backend and runs tests without downloading models. Coverage includes translation logic, OCR, API consent and requests, local persistence, model downloads, and caching. HTTP tests use temporary local services and do not require real API keys. This does not replace a full MLX build or evaluation of actual model translation quality.

## Project structure

| Path | Contents |
| --- | --- |
| `Sources/LinguaMac/` | SwiftUI app, inference adapters, OCR, and local workspace |
| `Sources/TranslationCore/` | Translation logic, model catalog, and interface localization resources |
| `Tests/TranslationCoreTests/` | Automated tests |
| `Distribution/` | App Store project configuration, resources, and privacy manifest |
| `Vendor/mlx-swift/` | Vendored MLX Swift dependency and its original licenses |
| `scripts/` | Checks, model packaging, license collection, and archiving |
| `website/` | Support and privacy website generator |
| `docs/` | Build instructions, model research, and development notes |

## Known limitations

- Local inference targets Apple Silicon; Intel Macs have not been verified.
- Models can mistranslate. Terminology hints and number checks do not guarantee accuracy; review important material manually.
- Long text is split into chunks without carrying full-document context between chunks.
- OCR reading order for complex columns or tables may need manual cleanup. Original image layout reconstruction is not supported.
- Voice and conversational translation are not included. Local models are limited to those supported in the model library.
- Lingua currently manages its own models and has not integrated with Luoke's shared model service.

## Contributing and support

Bug reports, suggestions, and pull requests are welcome through [GitHub Issues](https://github.com/xingj404-lab/Lingua/issues). Read the [contribution guide](CONTRIBUTING.md) and [code of conduct](CODE_OF_CONDUCT.md) before contributing. Follow the [security policy](SECURITY.md) to report vulnerabilities privately. These supporting documents are currently in Chinese.

For implementation history, see the [development notes](docs/development-notes.md); for model selection, see [model research](docs/model-research.md) (both in Chinese).

## License and acknowledgments

Lingua's original code is released under the **[MIT License](LICENSE)**. Copyright © 2026 xingj404-lab.

Third-party dependencies, model weights, tokenizers, and related resources retain their own licenses. The root MIT license does not replace them. In particular, Hy-MT2 models are governed by their own license, not this repository's MIT license. See [third-party notices](THIRD_PARTY_NOTICES.md) (Chinese).

Thanks to MLX Swift, MLX Swift LM, the Hugging Face Swift toolchain, and the Hy-MT2 and Qwen model communities.
