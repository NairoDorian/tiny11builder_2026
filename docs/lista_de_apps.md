# Windows 11 App Removal Reference

This document lists the Windows AppX/UWP packages removed by the Ultimate Edition builder.
It is adapted from the prismatecas-ui fork's documentation with additional entries
incorporated from all other forks in the reference set.

## Removed Packages

### Microsoft Edge & Related
- `Microsoft.MicrosoftEdge`
- `Microsoft.MicrosoftEdgePkgDice`
- `Microsoft.MicrosoftEdgePkgMetrics`
- `Microsoft.MicrosoftEdgePkgFlightingSe`
- `Microsoft.EdgePkgPolicy`
- `Microsoft.EdgeUpdate`
- `microsoft.windows.devhome` (from revamped/reforged)
- `Microsoft.Edge.GameAssist` (from zPoche v2)

### Microsoft 365 / Office
- `Microsoft.DesktopSchool.Office`
5. `Microsoft.DesktopSchool.Office`
- `Microsoft.Office.DesktopSchool`
- `Microsoft.Office.OneDrive`
- `Microsoft.Office.UWP`

### Teams & Chat
- `MicrosoftTeamsDesktop`
(teams machine-wide installer)
- `Microsoft.YourPhone` (cross-device experience)

### Bing & Search
- `Microsoft.BingFinance`
- `Microsoft.BingNews`
- `Microsoft.BingSports`
- `Microsoft.BingWeather`
- `Microsoft.BingCalendar`
- `Microsoft.BingFood` (new in 24H2)
- `Microsoft.BingGames` (legacy)

### Gaming
- `Microsoft.XboxGameOverlay`
- `Microsoft.XboxGamingOverlay`
- `Microsoft.GameBar`
- `Microsoft.SkypeApp`
- `Microsoft.ZuneMusic` / `Microsoft.ZuneVideo` (legacy)
- `Microsoft.Microsoft.WindowsApps` (Xbox-related stubs)

### Media & Camera
- `Microsoft.WindowsCamera` (optional - user can re-enable)
- `Microsoft.ScreenSketch`
- `Microsoft.Microsoft.ScreenSketch`
- `Microsoft.MixedReality.Portal`
- `Microsoft.Print3D`
- `Microsoft.WindowsMaps`
- `microsoft.windowscommunicationsapps` (Mail & Calendar)

### Finance & Productivity
- `Microsoft.BingFinance`
- `Microsoft.Wallet`
- `Microsoft.YourPhone`
- `Microsoft.Whiteboard`

### Social & News
- `Microsoft.Getstarted`
- `Microsoft.MicrosoftSolitaireCollection`
- `Microsoft.Windows.Scratch` (developer tool)
- `Microsoft.Xbox.TCUI`
- `Microsoft.Xbox.App`
- `Microsoft.Xbox.WI` (legacy)

### System Apps (Core mode only)
- `MicrosoftWindows.Client.WebExperience` (Widgets, Search Highlights)
- `Microsoft.Windows Widgets` (Windows Widgets)
- `MicrosoftWindows.Client.Core` (Windows Spotlight, Widgets)
- `MicrosoftCorporationII.Win32DesktopPreview` (Insider Hub)
- `Microsoft.GamingApp`
- `Microsoft.ZuneMusic`
- `Microsoft.ZuneVideo`
- `Microsoft.5457dhmsd2.lmhk` (Get Help)

### Copilot & AI (24H2+)
- `MicrosoftWindows.Client.CopilotUtils` (from revamped/reforged)
- `Microsoft.Windows.Ai.Copilot` (from revamped)
- `Microsoft.Windows.ShellExperienceHost` (AI/recall in 24H2)
- `Microsoft.Delegate` (Recall container)

## Simple App Removal List

For quick reference, the following are the appx packages removed by default:

```
Microsoft.BingCalendar
Microsoft.BingFinance
Microsoft.BingGames
Microsoft.BingNews
Microsoft.BingSports
Microsoft.BingWeather
Microsoft.BingFood
Microsoft.DesktopSchool.Office
Microsoft.GamingApp
Microsoft.Getstarted
Microsoft.Microsoft.Edge.GameAssist
Microsoft.MicrosoftOfficeHub
Microsoft.MicrosoftSolitaireCollection
Microsoft.Office.DesktopSchool
Microsoft.Office.OneDrive
Microsoft.Office.UWP
Microsoft.People
Microsoft.Print3D
Microsoft.ScreenSketch
Microsoft.SkypeApp
Microsoft.Wallet
Microsoft.Whiteboard
Microsoft.Windows.Camera
Microsoft.Windows.LXSSWin
Microsoft.Windows.Maps
Microsoft.Windows.Shop
Microsoft.Windows.SoundRecorder
Microsoft.WindowsAppears
Microsoft.YourPhone
Microsoft.ZuneMusic
Microsoft.ZuneVideo
microsoft.windowscommunicationsapps
microsoft.windows.devhome
Microsoft.BingRetail
Microsoft.5457dhmsd2.lmhk
Microsoft.Delegate
MicrosoftWindows.Client.CopilotUtils
Microsoft.Windows.Ai.Copilot
MicrosoftWindows.Client.WebExperience
Microsoft.Windows.SocialExperience
```
