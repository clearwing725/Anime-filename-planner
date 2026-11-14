using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

internal static class PlannerRename
{
    internal sealed record Move(string Source, string Destination);
    private static readonly StringComparer WindowsNames = StringComparer.OrdinalIgnoreCase;

    internal static Move[] Preview(string[] sources, string[] names)
    {
        if (sources.Length != names.Length || names.Length is < 1 or > 500)
            throw new IOException($"Select {names.Length} files to match the generated names.");

        var selected = new HashSet<string>(sources, WindowsNames);
        var destinations = new HashSet<string>(WindowsNames);
        var moves = new Move[names.Length];
        for (int i = 0; i < names.Length; i++)
        {
            string name = names[i];
            string source = sources[i];
            if (name.Length is < 1 or > 255 || name.EndsWith('.') || name.EndsWith(' ') ||
                name.Any(character => character < ' ' || "<>:\"/\\|?*".Contains(character)) ||
                Regex.IsMatch(name.Split('.')[0].TrimEnd(), @"\A(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])\z",
                    RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
                throw new IOException($"Invalid Windows filename: {name}");
            if (!File.Exists(source)) throw new IOException($"File is missing: {source}");
            if (!WindowsNames.Equals(Path.GetExtension(source), Path.GetExtension(name)))
                throw new IOException($"The extensions must match for {Path.GetFileName(source)} and {name}.");

            string destination = Path.Combine(Path.GetDirectoryName(source)!, name);
            if (!destinations.Add(destination) || (!WindowsNames.Equals(source, destination) &&
                (selected.Contains(destination) || File.Exists(destination) || Directory.Exists(destination))))
                throw new IOException($"That filename is already in use: {destination}");
            moves[i] = new Move(source, destination);
        }
        if (selected.Count != sources.Length) throw new IOException("Each source file must be selected once.");
        return moves;
    }

    internal static int Apply(Move[] moves)
    {
        var completed = new List<Move>();
        try
        {
            foreach (var move in moves)
            {
                if (move.Source == move.Destination) continue;
                File.Move(move.Source, move.Destination, overwrite: false);
                completed.Add(move);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            var remaining = new List<string>();
            for (int i = completed.Count - 1; i >= 0; i--)
            {
                var move = completed[i];
                try { File.Move(move.Destination, move.Source, overwrite: false); }
                catch (Exception rollback) when (rollback is IOException or UnauthorizedAccessException)
                {
                    remaining.Add($"{move.Destination} → {move.Source}");
                }
            }
            string result = remaining.Count == 0 ? "No names were changed." :
                "These files could not be restored:\n" + string.Join('\n', remaining);
            throw new IOException($"Rename stopped. {error.Message}\n\n{result}", error);
        }
        return completed.Count;
    }
}
