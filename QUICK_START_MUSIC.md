# Apple MusicKit - Quick Start Guide

## Fast Track to Get Apple Music Working

### What You Need
1. **Apple Developer Account** ($99/year)
2. **MusicKit Key** (free to create)

### 5-Minute Setup

#### 1. Create MusicKit Key (2 minutes)
```
1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Click "Keys" in sidebar
3. Click "+" to create new key
4. Name: "NihonGoStart MusicKit"
5. Check "MusicKit" capability
6. Click "Generate" and DOWNLOAD the .p8 file immediately
```

#### 2. Get Your Credentials (2 minutes)
```bash
# In Terminal, navigate to your downloaded .p8 file
cd ~/Downloads

# Base64 encode the private key
cat AuthKey_XXXXXXXXXX.p8 | base64 | tr -d '\n'

# Copy the entire output - this is your private key
```

**Find your Team ID & Key ID**:
- Team ID: From .p8 filename or https://developer.apple.com/account (Membership Details)
- Key ID: From .p8 filename (10 characters, e.g., "ABC1234567")

#### 3. Update Secrets.swift (1 minute)
Open `/NihonGoStart/Secrets.swift`:

```swift
// Apple Music Kit
static let appleMusicTeamId = "YOUR_TEAM_ID"        // 10 chars
static let appleMusicKeyId = "YOUR_KEY_ID"          // 10 chars
static let appleMusicPrivateKey = "BASE64_KEY_HERE"  // From step 2
```

#### 4. Build & Run
```bash
# Open in Xcode
open NihonGoStart.xcodeproj

# Or build from command line
xcodebuild -scheme NihonGoStart build
```

### Test It

Search for these popular J-Pop artists:
- **YOASOBI** (夜よ駆けろ)
- **Ado** (うっせぇわ)
- **King Gnu** (白日)

You should see:
- ✅ Search results with album art
- ✅ Play button works (30s preview)
- ✅ Lyrics button opens lyrics view
- ✅ Japan/US storefront toggle

### Troubleshooting

**"Setup Required" message**:
→ Check all 3 fields in Secrets.swift are filled

**"No songs found"**:
→ Try different search terms
→ Switch between Japan/US storefronts

**Preview not playing**:
→ Check network connection
→ Some tracks don't have previews
→ Try "Open in Apple Music"

**Build errors**:
→ Clean build (Cmd+Shift+K)
→ Verify no typos in Secrets.swift
→ Check Team ID/Key ID are exactly 10 characters

### Key Features

| Feature | Status |
|---------|--------|
| Search Japanese songs | ✅ Working |
| Play previews | ✅ Working |
| Fetch lyrics | ✅ Working |
| Full playback | 🔜 Future |
| Japan storefront | ✅ Working |
| US storefront | ✅ Working |

### What's Different from Spotify?

**Better**:
- ✅ Synchronized lyrics
- ✅ Better Japanese music catalog
- ✅ No user login required
- ✅ Storefront selection (JP/US)

**Different**:
- Color: Red (Apple) instead of Green (Spotify)
- Preview-only (full playback coming soon)

### Need Help?

- **Full Guide**: See `APPLE_MUSIC_SETUP.md`
- **Implementation Details**: See `MIGRATION_SUMMARY.md`
- **Apple Docs**: https://developer.apple.com/documentation/applemusicapi

---

**Pro Tip**: Keep your .p8 file secure! You can only download it once. Store it safely in case you need to regenerate your base64 key.
