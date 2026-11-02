#!/usr/bin/env python3
"""Build the English support website. Requires only Python 3."""
import argparse
import html
import json
import re
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--draft', action='store_true', help='Allow missing contact information for local preview only')
args = parser.parse_args()
config = json.loads((ROOT / 'site.json').read_text())
email, owner = config['contact_email'].strip(), config['copyright_owner'].strip()
if not args.draft and (not re.fullmatch(r'[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+', email) or not owner):
    raise SystemExit('Set a real contact_email and copyright_owner in website/site.json before building for deployment.')
email = html.escape(email or 'CONTACT_EMAIL_REQUIRED', quote=True)
owner = html.escape(owner or 'COPYRIGHT_OWNER_REQUIRED')
dist = ROOT / 'dist'
(dist / 'assets').mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT.parent / 'Assets/LinguaLogo.svg', dist / 'assets/logo.svg')

def page(title, description, body, current):
    def nav(name, url):
        active = ' aria-current="page"' if name == current else ''
        return f'<a href="{url}"{active}>{name}</a>'
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} · Lingua</title><meta name="description" content="{description}"><meta name="theme-color" content="#fafafa"><link rel="icon" href="/assets/logo.svg" type="image/svg+xml"><link rel="stylesheet" href="/assets/style.css"></head>
<body><a class="skip" href="#main">Skip to content</a><header><a class="brand" href="/" aria-label="Lingua support home"><img src="/assets/logo.svg" alt="" width="42" height="42">Lingua</a><nav aria-label="Main navigation">{nav('Support', '/support/')}{nav('Privacy', '/privacy/')}</nav></header><main id="main">{body}</main><footer><p>© 2026 {owner}. Lingua for Mac.</p><div><a href="/support/">Support</a><a href="/privacy/">Privacy policy</a></div></footer></body></html>'''

faqs = [
('Can I translate without an internet connection?', 'Yes. Lingua includes a translation model that runs on your Mac. After installing the app, you can use the built-in model offline without an account, an API key, or an additional model download. Optional model downloads and remote API services need a connection.'),
('Which Macs can run Lingua?', 'Lingua requires an Apple Silicon Mac (M1 or later) running macOS 14 or later. The local AI model uses memory in addition to its storage space. Close other memory-heavy apps if your Mac is under pressure.'),
('How do I translate a screenshot or an image?', 'Paste a screenshot into the translation workspace, drag in an image, or select one from the Import menu. Lingua recognizes the text on your Mac. Check the recognized text, select your translation direction, and choose Translate. Complex columns and tables may need manual cleanup. Lingua translates the extracted text; it does not replace text inside the original image.'),
('The first translation is taking longer. What should I do?', 'The local model needs time to load into memory before it can translate. Wait for the model-ready status, then try a short passage. If the app reports an error, check your available memory and restart Lingua. Speed depends on your Mac, the model, and the length of the text.'),
('How can I improve a translation?', 'Check the source and destination languages, correct any image recognition errors, and try a shorter passage. Use translation options to choose a subject area and style, or add preferred terms to the glossary. AI may make mistakes; review important names, numbers, and specialist terminology.'),
('Do I need to download another model?', 'No. The built-in model is enough to start. Additional supported models are optional. To download one, open Settings, choose a download source, and select Download in the model library. After the download finishes, select Use. If a download fails, check the selected source, your connection, and available storage, then retry.'),
('What happens if I connect an API service?', 'API mode is optional. You provide a compatible API address, model ID, and any required credentials. Lingua asks for permission before sending a request to each configured address. Your source text and relevant glossary terms then go to that service. Use Local model in Settings to return to translation on your Mac.'),
('How do I delete history or remove saved credentials?', 'Delete individual records in History, or use the clear-history action under Settings → Data & privacy. Glossary entries can be deleted individually. In API settings, you can remove a saved API key and revoke API sending permissions under Data & privacy. Removing a key from Lingua does not revoke it with the provider.'),
('Can I import and export text?', 'Yes. Import TXT or Markdown files through the Import menu or by dragging a file into the workspace. Copy the translation or export it as a TXT file. Lingua currently supports text and image text recognition, rather than voice or live conversation translation.')]
faq_html = ''.join(f'<details><summary>{q}</summary><p>{a}</p></details>' for q,a in faqs)
support = f'''<section class="hero"><p class="eyebrow">Lingua / Support</p><h1>A little help.<br>Then back to your words.</h1><p class="intro">Get started, fix a snag, or get in touch. Your translation workspace is right here on your Mac.</p><span class="status"><span class="dot"></span>Built-in model · Works offline</span></section>
<section class="contact" aria-labelledby="contact-title"><div><h2 id="contact-title">Let's work it out.</h2><p>Questions, bug reports, and feedback are welcome.</p><p class="email">{email}</p></div><a href="mailto:{email}?subject=Lingua%20support">Email support ↗</a></section>
<section class="section"><h2>Include a few details</h2><div class="grid"><div><h3>Tell us what happened</h3><p>Share your Lingua version, macOS version, Mac model, the translation mode you used, and the steps that led to the issue. Include the exact error message if there is one.</p></div><div><h3>Keep private things private</h3><p>Do not send API keys, passwords, or confidential documents. Remove personal details from screenshots. A short, non-sensitive example is usually enough.</p></div></div></section>
<section class="section"><h2>Common questions</h2>{faq_html}</section>
<section class="section"><h2>Your Mac. Your choice.</h2><p>Local translation and image text recognition run on your device. Optional API connections and model downloads have different data flows.</p><a href="/privacy/">Read the privacy policy →</a></section>'''

sections = [
('who', 'Who we are', f'This policy explains how Lingua for Mac and this support website handle information. Lingua is provided by {owner}. For privacy questions, contact <a class="email" href="mailto:{email}">{email}</a>. Lingua has no app account, advertisements, tracking SDKs, or developer-operated translation server.'),
('local', 'Translation on your Mac', 'Image text recognition (OCR) and local AI translation run on your Mac. When you use a local model, your source text, translated text, glossary entries, original images, and local performance measurements are not sent to us. Original images stay in the current session; history saves recognized text and translations, not the image files. Clipboard images are read when you paste them. Temporary clipboard image files are removed after recognition.'),
('api', 'Optional API services', 'API translation is optional. Before the first request to each configured API address, Lingua asks for your permission. If you agree, the request includes your source text (including recognized image text), relevant glossary entries, language and style instructions, and model ID. Original image files are not sent. Your API key is sent to your configured service for authentication.<br><br>The service processes requests under its own terms and privacy policy, including its own retention practices. Depending on the service you choose, processing may take place in another country. Check its policy before submitting sensitive content. Changing the API address requires permission again. You can revoke sending permissions in Settings. Revocation does not erase requests a provider has already received; contact that provider about its records.'),
('models', 'Optional model downloads', 'The built-in translation model works without an additional download. Other supported models are downloaded when you choose Download. The selected source—Hugging Face, HF-Mirror, or a custom download endpoint—receives ordinary network information such as your IP address and the model files requested. These downloads do not send your translation text, glossary entries, or API key. Download sources are third-party services with their own privacy practices.'),
('storage', 'Local storage and your controls', 'Lingua stores recent translations (up to 100 records), glossary entries, preferences, and downloaded models locally in its macOS app sandbox. There is no developer-operated cloud sync. These local workspace files are not encrypted by Lingua itself; macOS security features such as FileVault can help protect your device.<ul><li>Delete individual translations in History, or clear history in Settings.</li><li>Delete glossary entries individually in the glossary.</li><li>Manage optional downloaded models in Settings.</li><li>Revoke API sending permissions in Settings.</li><li>API keys are used in memory and stored in macOS Keychain only when you choose Save. You can remove saved keys in API settings. This does not revoke a key with its provider.</li></ul>Uninstalling the app may leave local container data or Keychain entries behind. Use the in-app controls and macOS tools to manage those records. We cannot access or remotely delete files stored only on your Mac.'),
('permissions', 'File access and diagnostics', 'Lingua accesses files you select for import or export. It uses the network for optional API requests and model downloads. This version does not include a developer-operated analytics or automatic crash-upload service. Any diagnostics you independently choose to share with Apple are handled under Apple’s applicable settings and privacy practices.'),
('contact', 'When you contact support', 'If you email us, we receive your email address and the message, attachments, and technical details you choose to share. We use this information to respond, troubleshoot, and improve Lingua. Our email provider processes correspondence to deliver and store it. Do not include API keys, passwords, or confidential source material.<br><br>We retain support correspondence only as long as reasonably needed to handle your request and related follow-up, or to meet applicable legal requirements. To request access, correction, or deletion of support information you sent us, email the contact address above. The rights available to you depend on applicable law.'),
('website', 'This website', 'These support pages do not include advertising, analytics scripts, tracking pixels, contact forms, or cookies set by our own site code. Fonts and visual assets are served with the site.<br><br>The website is hosted on Cloudflare. Delivering and protecting the site involves processing network request information such as IP addresses, requested URLs, browser information, and request times. Hosting and security processing is separate from local translation in the app. See <a href="https://www.cloudflare.com/privacypolicy/" rel="noopener noreferrer">Cloudflare’s privacy policy</a> for its practices.'),
('sharing', 'Sharing and security', 'We do not sell your personal information or use it for targeted advertising. Service providers involved in hosting this website or handling support email process the information needed for those services. We may disclose information we hold when required by law or to protect legal rights and security. We use reasonable safeguards for information we handle, but no system can guarantee absolute security.'),
('changes', 'Changes to this policy', 'We will update this page and its effective date when these practices change. If future app versions materially change how information is handled, we will update the policy and relevant in-app permission prompts.')]
toc = ''.join(f'<a href="#{key}">{title}</a>' for key,title,_ in sections)
articles = ''.join(f'<section id="{key}"><h2>{title}</h2><div>{"<p>" + content.replace("<ul>", "</p><ul>").replace("</ul>", "</ul><p>") + "</p>"}</div></section>' for key,title,content in sections)
privacy = f'''<div class="policy"><section class="hero"><p class="eyebrow">Lingua / Privacy</p><h1>Your words belong<br>on your Mac.</h1><p class="intro">Local translation stays local. Here is what happens when you use Lingua, connect a service, or visit this website.</p><p class="meta">Effective date: October 15, 2026</p></section><div class="policy-layout"><aside class="toc" aria-label="Policy contents">{toc}</aside><article><div class="summary-box"><strong>The short version</strong><p>We do not receive your local translations or images. Optional API mode sends text to the service you choose. Model downloads, support email, and website visits involve their respective service providers.</p></div>{articles}</article></div></div>'''
for route in ['', 'support']:
    dest = dist / route / 'index.html'
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(page('Support', 'Help with Lingua for Mac: offline AI translation, image text recognition, local models, API connections, and privacy.', support, 'Support'))
(dist / 'privacy').mkdir(exist_ok=True)
(dist / 'privacy/index.html').write_text(page('Privacy policy', 'How Lingua handles local translation, optional API requests, model downloads, local storage, and support information.', privacy, 'Privacy'))
(dist / '404.html').write_text(page('Page not found', 'Find Lingua support and privacy information.', '<section class="not-found"><p class="eyebrow">404 / Page not found</p><h1>Lost in translation?</h1><p>This page is not here. <a href="/support/">Go to Lingua support →</a></p></section>', ''))
if not args.draft:
    with zipfile.ZipFile(ROOT / 'lingua-cloudflare-pages.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        for file in sorted(dist.rglob('*')):
            if file.is_file():
                z.write(file, file.relative_to(dist))
    print('Built dist/ and lingua-cloudflare-pages.zip. Support: /support/ · Privacy: /privacy/')
else:
    print('Local preview built. Contact information is still required before deployment.')
