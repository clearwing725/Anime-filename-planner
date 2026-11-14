# Anime Filename Planner

Generate season-based anime filenames for Plex and Jellyfin. Enter a series name, season number, file extension, and episode range. You can convert absolute episode numbers into season numbers and group episodes that share one video file.

## Use the planner

- **In a browser:** Download the source ZIP from this repository's **Code** menu, extract it, and open `index.html` in Edge or Chrome. The planner works offline and needs no API keys.
- **On Windows (64-bit):** Open the latest successful run under **Actions → Windows build and tests**, download **Anime-Filename-Planner-Windows-x64** from **Artifacts**, extract the ZIP, and open `Anime-Filename-Planner.exe`. If the app asks for WebView2, install the [Evergreen Runtime from Microsoft](https://developer.microsoft.com/microsoft-edge/webview2/).

The app opens with the InuYasha example. Episodes 166–167 map to `InuYasha (2000) - S06E28-E29.mkv`. Click **Clear** to start your own list. **Copy list** copies the suggested names, and **Download .txt** saves them as text. You apply the suggested names to your media files yourself. Use the episode order configured in your server. [Plex naming guide](https://support.plex.tv/articles/naming-and-organizing-your-tv-show-files/) · [Jellyfin naming guide](https://jellyfin.org/docs/general/server/media/shows/)

## Check a change

GitHub Actions runs the browser and export checks, builds the Windows executable, and tests startup, clipboard, and the Save dialog. Open the run to see which check passed or failed. A passing run verifies the cases the tests cover.

To reproduce the checks locally, install the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) and [Node.js 24](https://nodejs.org/). Open a terminal in the project folder and run:

```text
npm ci --ignore-scripts
npx playwright install chromium
npm test
dotnet run --project tests/HostChecks/HostChecks.csproj --configuration Release
dotnet publish Planner.csproj --configuration Release --output artifacts
npm run test:windows
```

The last command requires Windows, WebView2, and an interactive desktop. If you change the inline script or stylesheet in `index.html`, update its Content Security Policy SHA-256 hash. Hash the block contents without the surrounding tags, using UTF-8 and LF line endings.
