# Xcode URL Scheme Configuration Guide

## Step-by-Step Instructions

### Step 1: Open Xcode Project

1. Open `NihonGoStart.xcodeproj` in Xcode
2. Select the **NihonGoStart** project in the Project Navigator (left sidebar)
3. Select the **NihonGoStart** target (main app, NOT the widget)

### Step 2: Navigate to Info Tab

1. Click the **Info** tab at the top of the settings area
2. Scroll down to the **URL Types** section
3. If you don't see it, it may be collapsed - click the disclosure triangle

### Step 3: Add OAuth Callback URL Scheme

1. Click the **+** button next to "URL Types"
2. Configure the new URL type:

   **Identifier:**
   ```
   com.ziqiyang.nihongostart.spotify
   ```

   **URL Schemes:**
   ```
   nihongostart
   ```
   (Click in the URL Schemes box, press Enter, type `nihongostart`, press Enter)

   **Role:**
   ```
   Editor
   ```
   (Select from dropdown menu)

Your configuration should look like:
```
URL Types
  ├─ Item 0 (Self)
  │   ├─ Identifier: com.ziqiyang.nihongostart.spotify
  │   ├─ URL Schemes: nihongostart
  │   └─ Role: Editor
```

### Step 4: Add Spotify App URL Scheme (Optional but Recommended)

This allows opening tracks directly in the Spotify app:

1. Click the **+** button again
2. Configure:

   **Identifier:**
   ```
   com.spotify.client
   ```

   **URL Schemes:**
   ```
   spotify
   ```

   **Role:**
   ```
   None
   ```

Final configuration:
```
URL Types
  ├─ Item 0 (Self)
  │   ├─ Identifier: com.ziqiyang.nihongostart.spotify
  │   ├─ URL Schemes: nihongostart
  │   └─ Role: Editor
  └─ Item 1
      ├─ Identifier: com.spotify.client
      ├─ URL Schemes: spotify
      └─ Role: None
```

### Step 5: Build and Test

1. Clean build folder: **Product → Clean Build Folder** (Cmd+Shift+K)
2. Build and run (Cmd+R)
3. Navigate to Songs tab
4. Tap "Login with Spotify"
5. Verify the authentication flow works

---

## Alternative: Info.plist Method

If your project uses a physical `Info.plist` file (in the `NihonGoStart` folder):

1. Open `Info.plist`
2. Right-click → **Open As → Source Code**
3. Add before the final `</dict>` tag:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.ziqiyang.nihongostart.spotify</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>nihongostart</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
    </dict>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.spotify.client</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>spotify</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>None</string>
    </dict>
</array>
```

4. Save and close
5. Clean build folder
6. Build and run

---

## Verification

### Test URL Scheme

You can test if the URL scheme is registered correctly:

1. Open Safari on iOS Simulator or device
2. Enter: `nihongostart://test` in the address bar
3. The app should open (or prompt to open)

### Test OAuth Flow

1. Launch app
2. Go to Songs tab
3. Tap "Login with Spotify"
4. Safari should open with Spotify login
5. After login, you should be redirected back to the app
6. User profile should appear at the top

---

## Troubleshooting

### URL Scheme Not Working

**Symptom**: Tapping "Login with Spotify" does nothing

**Solutions**:
1. Verify URL scheme is added to correct target (main app, not widget)
2. Clean build folder and rebuild
3. Check for typos in URL scheme (must be exactly `nihongostart`)
4. Ensure app is properly installed (delete and reinstall)

### Redirect URI Error

**Symptom**: Spotify shows "Invalid redirect URI" error

**Solutions**:
1. Verify `nihongostart://callback` is added in Spotify Dashboard
2. Check for exact match (no trailing slashes, lowercase)
3. Ensure Spotify app settings are saved

### Can't Open in Spotify App

**Symptom**: "Open in Spotify" button opens web player instead of app

**Solutions**:
1. Verify Spotify app is installed on device
2. Add `spotify://` to URL types as shown in Step 4
3. Test Spotify deep link: `spotify://track/3n3Ppam7vgaVa1iaRUc9Lp`

---

## Common Mistakes

❌ **Wrong URL Scheme**
- Incorrect: `NihonGoStart://callback`
- Correct: `nihongostart://callback`

❌ **Wrong Target**
- Incorrect: Added to widget target
- Correct: Added to main app target

❌ **Missing Scheme in Array**
- Incorrect: Just typed "nihongostart" without pressing Enter
- Correct: Press Enter to add it to the array

❌ **Forgot Role**
- Incorrect: Left Role as "Viewer" or blank
- Correct: Set to "Editor"

---

## Additional Resources

- [Apple: Defining a Custom URL Scheme](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
- [Apple: Handling URLs in Your App](https://developer.apple.com/documentation/xcode/handling-urls-in-your-app)
- [Spotify: Authorization Guide](https://developer.spotify.com/documentation/web-api/concepts/authorization)

---

## Checklist

Before testing the OAuth flow, verify:

- [ ] URL scheme `nihongostart` added to main app target
- [ ] Redirect URI `nihongostart://callback` added in Spotify Dashboard
- [ ] Client ID in Secrets.swift matches Spotify Dashboard
- [ ] Scopes are enabled in Spotify Dashboard
- [ ] App builds without errors
- [ ] App installs on device/simulator
- [ ] Safari can open `nihongostart://test` URL

All checked? You're ready to test!
