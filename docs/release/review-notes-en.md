# Draft App Review Notes

Lingua is a native macOS text and image-OCR translation app for Apple Silicon. It does not provide voice or conversation translation. The initial release is free, with no in-app purchase, account registration, or developer-operated translation server.

The complete Hy-MT2-1.8B-4bit translation model is included in the application bundle. No model download, API Key or account is required to review the core functionality. First launch initializes the local model and shows its loading/warmup status. Select the local model in Settings if another backend was previously selected.

Suggested review steps:
1. Launch the app on an Apple Silicon Mac running macOS 14 or later; wait for the local model ready status.
2. Use the default automatic Chinese/English direction and type `Hello, welcome.` in the source editor. Press Return to translate; Shift+Return inserts a newline.
3. Import an image containing text, or paste a screenshot from the clipboard. OCR runs locally. Click the image attachment to view the original.
4. View the glossary and translation history in the sidebar. Privacy Policy and Open-source Licenses are in Settings > Data & Privacy.

Optional model downloads in the curated model library consist of model weights/tokenizer/configuration data supported by the included runtime; the app does not download executable code, plug-ins or arbitrary new runtimes. The built-in model remains usable offline. Each model shows its size and download state.

Optional API translation supports OpenAI-compatible endpoints configured by the user. The user provides a model ID and API Key when required. The app identifies the endpoint and asks for explicit permission before the first text transmission to each address. Original image files are not uploaded. Permission can be revoked in Settings. Review of the app does not require using this optional mode or a reviewer's private API Key.

Before submission, the publisher must replace this draft with final support contact and public privacy-policy URL, confirm store metadata and ensure all statements match the submitted binary.
