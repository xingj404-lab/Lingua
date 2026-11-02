# Privacy Policy

Effective date: October 15, 2026

Lingua translates text and recognizes text in images. It has no app account, advertisements, tracking, or developer-operated translation server.

## Local translation
Image text recognition and the built-in translation model run on your Mac. Your source text, translated text, glossary, images, and performance measurements are not sent to the developer. Original images remain in the current session; history stores recognized text and translations, not image files. Clipboard images are read only when you paste them. Temporary clipboard image files are removed after recognition.

## API translation
API translation is optional. Before the first request to each configured API address, Lingua asks for permission. If you agree, source text (including recognized image text), relevant glossary entries, language and style instructions, and the model ID are sent to that address. Original image files are not sent. Your API Key is sent only to your configured API service for authentication. The service may retain or process submitted information under its own terms and privacy policy. Do not submit confidential information unless your agreement with that service permits it. Changing the API address requires consent again. You can revoke permissions in Settings; revocation cannot delete information already received by a provider.

## Model downloads
Optional models are downloaded only after you choose Download. Hugging Face, HF-Mirror, or a configured download mirror receives ordinary download requests including your IP address and requested model files, but no translation text, glossary, or API Key. The built-in model works without a download. Mirrors are third-party services.

## Storage and controls
Recent translations (up to 100 records), glossary entries, preferences, and downloaded models are stored locally in the app's sandbox. Individual history and glossary entries can be deleted in the app. Settings also provides a separate action to clear history. API Keys are used in memory and are written to the app’s local data directory only when you choose Save, separately for each service address. Credentials are stored as local plaintext files with directory and file permissions restricted to the current user. The app does not use the macOS Keychain. Removing a saved key does not revoke the key with its provider. Uninstalling the app may not remove all local data containers; use Settings and macOS controls to manage your data.

## Permissions and updates
Lingua requests access to files you select for import or export and uses the network for optional API requests and model downloads. This version has no analytics or crash-upload service. If future versions materially change these practices, this policy and the relevant permission prompts will be updated.
