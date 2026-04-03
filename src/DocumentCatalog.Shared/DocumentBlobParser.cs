using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace DocumentCatalog.Shared;

public static partial class DocumentBlobParser
{
    [GeneratedRegex(@"^(?<employeeId>\d+)[_-](?<documentType>[^.]+)", RegexOptions.Compiled)]
    private static partial Regex BlobNameRegex();

    public static bool TryParseEmployeeDocumentBlobName(
        string blobName,
        out int employeeId,
        out string documentTypeToken)
    {
        employeeId = 0;
        documentTypeToken = string.Empty;

        if (string.IsNullOrWhiteSpace(blobName))
            return false;

        var fileName = Path.GetFileNameWithoutExtension(blobName);
        var match = BlobNameRegex().Match(fileName);

        if (!match.Success)
            return false;

        if (!int.TryParse(match.Groups["employeeId"].Value, out employeeId))
            return false;

        documentTypeToken = match.Groups["documentType"].Value.Trim();

        return !string.IsNullOrWhiteSpace(documentTypeToken);
    }

    public static string HumanizeDocumentType(string token)
    {
        if (string.IsNullOrWhiteSpace(token))
            return string.Empty;

        return Regex.Replace(token, "([a-z])([A-Z])", "$1 $2")
            .Replace("_", " ")
            .Replace("-", " ")
            .Trim();
    }

    public static byte[] ComputeBlobNameHash(string blobName) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(blobName));
}