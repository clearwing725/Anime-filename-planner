using System;
using System.IO;
using System.Text;
using System.Text.Json;
using static PlannerExport;

internal static class HostChecks
{
    private static void Main()
    {
        const string sample = "InuYasha (2000) - S06E28-E29.mkv";
        string Message(string action, string text) => JsonSerializer.Serialize(new { action, text });
        void Check(bool passed, string label)
        {
            if (!passed) throw new Exception(label);
            Console.WriteLine("PASS: " + label);
        }

        Check(ReadExport(Message("copy", sample)) == ("copy", sample), "accepts valid copy");
        Check(ReadExport(Message("save", sample)) == ("save", sample), "accepts valid save");
        Check(ReadExport("{\"action\":\"copy\",\"text\":123}") == null, "rejects wrong field type");
        Check(ReadExport("[]") == null && ReadExport("{") == null, "rejects malformed or non-object messages");
        Check(ReadExport(Message("launch", sample)) == null, "rejects unknown commands");
        Check(ReadExport(Message("save", " \n")) == null && ReadExport(Message("copy", "\0")) == null,
            "rejects blank and NUL-containing exports");
        Check(ReadExport(Message("save", new string('a', MaxExportBytes))) != null &&
            ReadExport(Message("save", new string('é', MaxExportBytes / 2 + 1))) == null, "enforces UTF-8 size limits");
        Check(ReadExport("{\"action\":\"copy\",\"text\":\"\\ud800\"}") == null, "rejects invalid Unicode");
        var folder = Directory.CreateTempSubdirectory();
        try
        {
            string output = Path.Combine(folder.FullName, "export.txt");
            SaveExport(output, sample);
            Check(File.ReadAllText(output) == sample, "creates a new text file");
            string updated = "名\n🎬";
            SaveExport(output, updated);
            Check(File.ReadAllBytes(output).AsSpan().SequenceEqual(Encoding.UTF8.GetBytes(updated)),
                "replaces an existing file with UTF-8 text without a BOM");
            string blocked = Path.Combine(folder.FullName, "directory.txt");
            Directory.CreateDirectory(blocked);
            try
            {
                SaveExport(blocked, updated);
                throw new Exception("Expected export failure");
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            Check(Directory.GetFileSystemEntries(folder.FullName).Length == 2 && Directory.Exists(blocked),
                "cleans up after a failed replace");
        }
        finally
        {
            folder.Delete(recursive: true);
        }
    }
}
