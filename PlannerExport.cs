using System;
using System.IO;
using System.Text;
using System.Text.Json;

internal static class PlannerExport
{
    internal const int MaxExportBytes = 500 * 256;
    private const int MaxMessageLength = MaxExportBytes * 6 + 128;
    private static readonly UTF8Encoding ExportEncoding = new(encoderShouldEmitUTF8Identifier: false);

    internal static (string Action, string Text)? ReadExport(string json)
    {
        if (json.Length > MaxMessageLength) return null;

        try
        {
            using var message = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 4 });
            var root = message.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("action", out var actionValue) || actionValue.ValueKind != JsonValueKind.String ||
                !root.TryGetProperty("text", out var textValue) || textValue.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            string? action = actionValue.GetString();
            string? text = textValue.GetString();
            return action is ("copy" or "save" or "rename") && !string.IsNullOrWhiteSpace(text) &&
                !text.Contains('\0') && ExportEncoding.GetByteCount(text) <= MaxExportBytes
                ? (action, text)
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
        catch (InvalidOperationException)
        {
            // An invalid Unicode sequence in a JSON string can fail when it is read.
            return null;
        }
    }

    internal static void SaveExport(string destination, string text)
    {
        // Complete the write beside the destination before replacing an existing export.
        string temporary = Path.Combine(Path.GetDirectoryName(destination)!, Path.GetRandomFileName());
        var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        try
        {
            using (var writer = new StreamWriter(stream, ExportEncoding))
                writer.Write(text);
            File.Move(temporary, destination, overwrite: true);
        }
        catch
        {
            stream.Dispose();
            try { File.Delete(temporary); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            throw;
        }
    }
}
