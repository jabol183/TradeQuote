# Uploading TradeQuote to TestFlight

The **TestFlight** workflow (`.github/workflows/testflight.yml`) builds a signed release and uploads it to App Store Connect. All of the setup below can be done in a web browser, including on an iPad. No Mac is needed.

You only do this once.

## 1. Choose a bundle ID
This is the app's permanent ID, for example `com.yourname.tradequote`. It must be unique across the App Store, so `com.tradequote.ai` may already be taken.

developer.apple.com → **Certificates, IDs & Profiles** → **Identifiers** → **+** → *App IDs* → *App* → enter a description and the **Explicit** bundle ID → Continue → Register. You don't need to turn on any extra capabilities.

## 2. Create the app in App Store Connect
appstoreconnect.apple.com → **Apps** → **+** → **New App**
- Platform: iOS
- Name: anything not already used on the App Store (you can change it later)
- Bundle ID: the one from step 1
- SKU: any text, e.g. `tradequote`

## 3. Create an App Store Connect API key
App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**
- Access: **Admin**. Admin is needed so Apple can sign the app for you in the cloud.
- **Download the .p8 file.** You can only download it once.
- Note the **Key ID**, and the **Issuer ID** shown above the list of keys.

## 4. Find your Team ID
developer.apple.com → **Account** → **Membership details** → *Team ID* (10 characters).

## 5. Add them to GitHub
GitHub repo → **Settings** → **Secrets and variables** → **Actions**

**Secrets** tab → *New repository secret*:

| Name | Value |
|---|---|
| `APPSTORE_KEY_ID` | Key ID from step 3 |
| `APPSTORE_ISSUER_ID` | Issuer ID from step 3 |
| `APPSTORE_API_PRIVATE_KEY` | The full text of the .p8 file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

**Variables** tab → *New repository variable*:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID from step 4 |
| `BUNDLE_ID` | Bundle ID from step 1 |

Tip for iPad: open the .p8 file in the Files app with any text editor, select all, copy, and paste it into the secret.

## 6. Run it
GitHub → **Actions** → **TestFlight** → **Run workflow**. You can optionally type a version such as `1.0.0`.
You can also push a tag like `v1.0.1`. The tag's number becomes the version.

The build number is set automatically from the date and time. After the run turns green, Apple takes about 5–30 minutes to process the build.

## 7. Install it
App Store Connect → your app → **TestFlight**
- **Internal testing**: create a group, add yourself (your Apple ID must be a user on the team), then add the build. No review is needed.
- **External testing** (up to 10,000 people by email or public link): the first build of each version goes through a short Beta App Review.

Install the **TestFlight** app on the iPhone or iPad and accept the invite. Testers need iOS/iPadOS 26 or later.

The app already says it uses no non-exempt encryption, so App Store Connect won't ask the export-compliance question.

---

## Fallback: your own distribution certificate
If cloud signing fails (for example, the API key isn't Admin and you can't change it), the workflow can sign with your own certificate instead. Add these three secrets; the workflow detects them and switches automatically:

| Secret | What it is |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Your **Apple Distribution** certificate with its private key, as a .p12 file, base64-encoded |
| `P12_PASSWORD` | The password you set when exporting the .p12 |
| `BUILD_PROVISION_PROFILE_BASE64` | An **App Store** provisioning profile for your bundle ID (.mobileprovision), base64-encoded |

With these set, the team and bundle ID are read from the profile, so the two variables become optional.

Creating a .p12 needs a computer, either a Mac (Keychain Access → export) or any machine with `openssl`:
```sh
openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr -subj "/CN=TradeQuote Distribution"
# Upload dist.csr at developer.apple.com → Certificates → + → Apple Distribution, download distribution.cer
openssl x509 -inform DER -in distribution.cer -out dist.pem
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12   # choose a password; drop -legacy if your openssl rejects it
base64 -i dist.p12 | tr -d '\n'                      # → BUILD_CERTIFICATE_BASE64
base64 -i TradeQuote_AppStore.mobileprovision | tr -d '\n'   # → BUILD_PROVISION_PROFILE_BASE64
```
Create the profile at developer.apple.com → **Profiles** → **+** → *App Store Connect* → choose your App ID and the certificate.
