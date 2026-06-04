# CI/CD — building, testing & releasing MacDring

MacDring (and its sibling app **Zap**) ship via **GitHub Actions** on macOS runners.
Two workflows do the work:

| Workflow | Trigger | What it does |
|---|---|---|
| [`ci.yml`](workflows/ci.yml) | every pull request + push to `main` | `xcodebuild clean test` with **no code signing** — verifies the app builds and the XCTest suite passes |
| [`release.yml`](workflows/release.yml) | pushing a `v*` tag (e.g. `v1.2.0`) | builds Release → **codesigns (Developer ID)** → **notarizes** → **staples** → packages a **DMG** → creates a **GitHub Release** with the DMG attached |

Both run on `macos-14` (Apple Silicon) with a **pinned Xcode** (`16.2`). There are no third-party
dependencies, so there's nothing to cache or `pod install`.

> **Auto-updates (Sparkle)** are intentionally **not** wired up yet. When we want in-app
> "Update available" we'll add a Sparkle appcast step to `release.yml`.

---

## Cutting a release

The release is driven entirely by a **git tag** — no need to edit a version in the project.

```bash
git tag v1.2.0
git push origin v1.2.0
```

That's it. The workflow:

1. derives `MARKETING_VERSION` from the tag (`v1.2.0` → `1.2.0`) and uses the workflow run
   number as `CURRENT_PROJECT_VERSION` (a monotonic build number);
2. archives + exports a Developer-ID-signed `.app`;
3. notarizes and staples it (and the DMG) with Apple's `notarytool`;
4. publishes a GitHub Release named `MacDring 1.2.0` with auto-generated notes and the
   `MacDring-1.2.0.dmg` attached.

To re-do a botched release, delete the tag and Release on GitHub, then re-tag.

---

## One-time setup: repository (or org) secrets

Set these under **Settings → Secrets and variables → Actions**. Because MacDring and Zap use
the **same** Apple developer account, set them at the **organization** level and both repos
share one copy.

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | base64 of your **Developer ID Application** certificate + private key, exported as a `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | the password you set when exporting that `.p12` |
| `KEYCHAIN_PASSWORD` | any throwaway string — used to create an ephemeral keychain on the runner |
| `APPLE_TEAM_ID` | your 10-character Apple Developer Team ID |
| `AC_API_KEY_BASE64` | base64 of an **App Store Connect API key** (`.p8`) used for notarization |
| `AC_API_KEY_ID` | that API key's Key ID |
| `AC_API_ISSUER_ID` | that API key's Issuer ID |

### Generating them

**Developer ID certificate → `.p12` → base64**

1. In Keychain Access, find your *Developer ID Application: …* certificate (with its private key).
   If you don't have one, create it in the [Apple Developer portal](https://developer.apple.com/account/resources/certificates) → **Developer ID Application**.
2. Right-click it → **Export…** → save as `cert.p12`, set a password (this becomes
   `DEVELOPER_ID_P12_PASSWORD`).
3. `base64 -i cert.p12 | pbcopy` → paste as `DEVELOPER_ID_P12_BASE64`.

**App Store Connect API key (for notarization)**

1. [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
   → **Generate API Key** with the **Developer** role.
2. Download the `AuthKey_XXXXXXXXXX.p8` (you can only download it once).
3. `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy` → `AC_API_KEY_BASE64`; the **Key ID** →
   `AC_API_KEY_ID`; the **Issuer ID** (shown on that page) → `AC_API_ISSUER_ID`.

> An App Store Connect API key is preferred over an Apple-ID + app-specific-password: no 2FA
> prompts, and it's easy to revoke.

---

## Project requirements

For notarization to succeed, the app target must have:

- **Hardened Runtime** enabled (`ENABLE_HARDENED_RUNTIME = YES`) — required by notarization.
- **Developer ID** signing available (the certificate above).
- A **shared scheme** (`MacDring.xcscheme` in `xcshareddata`) with a Test action covering the
  test target — `ci.yml` relies on it.

CI itself needs none of the secrets (it builds with `CODE_SIGNING_ALLOWED=NO`), so it runs on
forked-PR branches too.

---

## Reusing this for Zap (and keeping them in sync)

Zap has the same shape, so its `ci.yml` / `release.yml` are identical except for three values
at the top of each file:

```yaml
env:
  PROJECT: Zap.xcodeproj
  SCHEME: Zap
  APP_NAME: Zap
```

Two ways to avoid drift between the two apps:

1. **Copy** these three files into Zap and edit the `env:` block (simplest).
2. **Reusable workflow:** move the build/test and release jobs into a `workflow_call` workflow
   (parametrised by `project` / `scheme` / `app_name`) hosted in one repo (or a shared
   `l-k-m/.github` repo), and have each app's workflow be a ~10-line caller. One place to fix,
   both apps benefit.

---

## Troubleshooting

- **Notarization rejected** — read the log:
  `xcrun notarytool log <submission-id> --key … --key-id … --issuer …`. The usual cause is a
  missing hardened runtime or an unsigned nested binary.
- **`create-dmg` exited non-zero but the DMG looks fine** — known quirk on headless runners
  (it can't set a volume icon). `release.yml` already tolerates this by checking the file exists.
- **`errSecInternalComponent` while signing** — the keychain wasn't unlocked or the
  partition list wasn't set; both are handled by the *Import Developer ID certificate* step.
- **Wrong Xcode** — bump the `xcode-version` in both workflows together; keep MacDring and Zap
  on the same version.
