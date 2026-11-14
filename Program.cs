using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new PlannerWindow());
    }
}

internal sealed class PlannerWindow : Form
{
    private const string PlannerPage = "https://anime-filename-planner.invalid/index.html";
    private readonly WebView2 browser = new() { Dock = DockStyle.Fill };
    private bool handlingAction;

    public PlannerWindow()
    {
        Text = "Anime Filename Planner";
        Size = new Size(1100, 850);
        MinimumSize = new Size(440, 620);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        Controls.Add(browser);
        Shown += InitializePlanner;
    }

    private async void InitializePlanner(object? sender, EventArgs args)
    {
        try
        {
            using var resource = Assembly.GetExecutingAssembly()
                .GetManifestResourceStream("Planner.index.html")
                ?? throw new IOException("The planner page is missing.");
            using var buffer = new MemoryStream();
            resource.CopyTo(buffer);
            byte[] page = buffer.ToArray();

            string profile = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AnimeFilenamePlanner", "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: profile);
            if (IsDisposed || Disposing) return;
            await browser.EnsureCoreWebView2Async(environment);
            if (IsDisposed || Disposing) return;

            var view = browser.CoreWebView2;
            view.Settings.IsStatusBarEnabled = false;
            view.Settings.AreDefaultContextMenusEnabled = false;
            view.Settings.AreHostObjectsAllowed = false;
            view.Settings.AreDevToolsEnabled = false;
            view.NavigationStarting += (_, navigation) => navigation.Cancel = navigation.Uri != PlannerPage;
            view.FrameNavigationStarting += (_, navigation) => navigation.Cancel = true;
            view.PermissionRequested += (_, request) => request.State = CoreWebView2PermissionState.Deny;
            view.DownloadStarting += (_, request) => request.Cancel = true;
            view.LaunchingExternalUriScheme += (_, request) => request.Cancel = true;
            view.NewWindowRequested += OpenReference;
            view.WebMessageReceived += HandleAction;

            // Serve the bundled page at a dedicated origin without a local server or a network request.
            view.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All,
                CoreWebView2WebResourceRequestSourceKinds.All);
            view.WebResourceRequested += (_, request) =>
            {
                request.Response = request.Request.Uri == PlannerPage && request.Request.Method == "GET"
                    && request.ResourceContext == CoreWebView2WebResourceContext.Document
                    ? environment.CreateWebResourceResponse(new MemoryStream(page, writable: false), 200, "OK",
                        "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff")
                    : environment.CreateWebResourceResponse(null, 403, "Forbidden", "");
            };
            view.Navigate(PlannerPage);
        }
        catch (WebView2RuntimeNotFoundException) when (!IsDisposed && !Disposing)
        {
            MessageBox.Show(this,
                "Install Microsoft Edge WebView2 Runtime, then open this app again.\n\n" +
                "Download it from https://developer.microsoft.com/microsoft-edge/webview2/",
                "WebView2 Runtime required", MessageBoxButtons.OK, MessageBoxIcon.Information);
            Close();
        }
        catch (Exception error)
        {
            if (IsDisposed || Disposing) return;
            MessageBox.Show(this, "The planner could not start.\n\n" + error.Message,
                Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
        }
    }

    private void OpenReference(object? sender, CoreWebView2NewWindowRequestedEventArgs request)
    {
        request.Handled = true;
        if (browser.CoreWebView2.Source != PlannerPage ||
            request.OriginalSourceFrameInfo?.Source != PlannerPage || !request.IsUserInitiated ||
            request.Uri is not ("https://www.tvmaze.com/shows/4247/inuyasha/episodes" or
                "https://support.plex.tv/articles/naming-and-organizing-your-tv-show-files/" or
                "https://jellyfin.org/docs/general/server/media/shows/"))
        {
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo(request.Uri) { UseShellExecute = true })?.Dispose();
        }
        catch (System.ComponentModel.Win32Exception)
        {
            ReportStatus("The reference could not open in your default browser.");
        }
    }

    private void HandleAction(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        if (handlingAction || args.Source != PlannerPage || browser.CoreWebView2.Source != PlannerPage) return;
        if (PlannerExport.ReadExport(args.WebMessageAsJson) is not { } export) return;

        handlingAction = true;
        // The save dialog runs its own message loop. Open it after the WebView2 callback returns.
        BeginInvoke(() => RunExport(export.Action, export.Text));
    }

    private void RunExport(string action, string text)
    {
        try
        {
            if (IsDisposed || Disposing || browser.CoreWebView2.Source != PlannerPage) return;
            if (action == "copy")
            {
                Clipboard.SetText(text.ReplaceLineEndings("\r\n"));
                ReportStatus("Filename list copied.");
                return;
            }

            using var picker = new SaveFileDialog
            {
                FileName = "anime-filenames.txt",
                Filter = "Text files (*.txt)|*.txt",
                DefaultExt = "txt",
                AddExtension = true,
                OverwritePrompt = true,
                RestoreDirectory = true
            };
            if (picker.ShowDialog(this) != DialogResult.OK)
            {
                ReportStatus("Save canceled.");
                return;
            }
            if (!string.Equals(Path.GetExtension(picker.FileName), ".txt", StringComparison.OrdinalIgnoreCase))
            {
                ReportStatus("Choose a filename ending in .txt.");
                return;
            }

            PlannerExport.SaveExport(picker.FileName, text);
            ReportStatus("Filename list saved.");
        }
        catch (ExternalException) when (action == "copy")
        {
            ReportStatus("The clipboard is busy. Try copying again.");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ReportStatus("The file could not be saved. Try a different folder.");
        }
        finally
        {
            handlingAction = false;
        }
    }

    private void ReportStatus(string text)
    {
        if (!IsDisposed && !Disposing && browser.CoreWebView2.Source == PlannerPage)
            browser.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { status = text }));
    }
}
