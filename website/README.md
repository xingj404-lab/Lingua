# Lingua support website

English-only, buildless static pages for Cloudflare Pages. No analytics, external fonts, JavaScript, forms, or dependencies.

## Contact information

Set the public support email and actual copyright owner in `site.json`, then run from the repository root:

```sh
python3 website/build.py
```

This produces `website/dist/` and `website/lingua-cloudflare-pages.zip`. The ZIP contains the deployable files at its root. A deployment build fails if contact information is missing. `--draft` is only for local preview.

## Deploy with Cloudflare Pages

In Workers & Pages, create a Pages project using Direct Upload / drag and drop. Upload `lingua-cloudflare-pages.zip` or the contents of `dist/`, then deploy. No build command or framework is needed for Direct Upload. For a Git-connected Pages project, use `python3 website/build.py` as the build command and `website/dist` as the output directory (with the repository root as root directory).

For an existing Pages project, upload as a new production deployment. Do not use a temporary preview URL in App Store Connect. Make sure the production site is public and does not require a login or Cloudflare Access authentication.

With the actual production hostname, use:

- Support URL: `https://YOUR-ACTUAL-HOSTNAME/support/`
- Privacy Policy URL: `https://YOUR-ACTUAL-HOSTNAME/privacy/`
- Optional Marketing URL: leave blank unless you have a separate product website.

Open both production URLs before entering them in App Store Connect. A local preview or successful build does not verify deployment.

## Maintenance

Update policy text in `build.py` when app data handling changes, then rebuild and deploy. The current policy reflects the app's local OCR, bundled model, optional API consent, model downloads, sandbox storage, and optional Keychain saving. Keep the in-app privacy policy consistent with the public policy. The effective date is October 15, 2026.

Do not enable Cloudflare Web Analytics, advertising scripts, or other data collection without updating the website privacy section accordingly.

Official deployment instructions: https://developers.cloudflare.com/pages/get-started/direct-upload/
