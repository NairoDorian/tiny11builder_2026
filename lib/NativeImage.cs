using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

// Native helpers for OFFLINE image servicing, compiled at run time by Add-Type
// (Windows PowerShell 5.1 and PowerShell 7). Nothing here targets the running
// Windows installation: callers pass paths inside an owned image mount and the
// HKLM keys of image hives they attached themselves.
//
//  * LoadHive / UnloadHive: RegLoadKeyW / RegUnLoadKeyW, returning the Win32
//    code instead of reg.exe's translated message.
//  * SetValue / DeleteValue / DeleteKeyTree: registry access through
//    REG_OPTION_BACKUP_RESTORE handles, so a protected image key can be written
//    without rewriting its ACL. Writes are read back.
//  * DeleteTree: deletes files and folders through backup-semantics handles with
//    POSIX delete + ignore-read-only, children first, using \\?\ paths. It never
//    changes ACLs or attributes, which matters because WinSxS hard links share
//    them with the surviving copy. Reparse points (junctions, symlinks, WOF/WIM
//    placeholders) are deleted as links and never followed.
public static class Tiny11NativeImage
{
    private static readonly IntPtr HKEY_LOCAL_MACHINE = new IntPtr(unchecked((int)0x80000002));
    private const int REG_OPTION_BACKUP_RESTORE = 0x4;
    private const int KEY_ALL_ACCESS = 0xF003F;
    private const uint DELETE = 0x00010000, FILE_READ_ATTRIBUTES = 0x80, FILE_LIST_DIRECTORY = 0x1;
    private const uint SHARE_ALL = 0x7, OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000, FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    private const uint FILE_ATTRIBUTE_DIRECTORY = 0x10, FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
    // FILE_DISPOSITION_FLAG_DELETE | POSIX_SEMANTICS | IGNORE_READONLY_ATTRIBUTE
    private const uint DISPOSITION_FLAGS = 0x1 | 0x2 | 0x10;
    private const int FileDispositionInfoEx = 21;

    // ---- privileges ------------------------------------------------------------------------------------------

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct TokenPrivilege { public int Count; public long Luid; public int Attributes; }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, int access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool LookupPrivilegeValue(string system, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivilege state, int length, IntPtr previous, IntPtr returned);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    // Enables a privilege on THIS process token (not a system setting). Child
    // processes such as dism.exe inherit the enabled state. Returns the Win32 code.
    public static int EnablePrivilege(string name)
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) return Marshal.GetLastWin32Error();
        try
        {
            long luid;
            if (!LookupPrivilegeValue(null, name, out luid)) return Marshal.GetLastWin32Error();
            TokenPrivilege state = new TokenPrivilege { Count = 1, Luid = luid, Attributes = 2 };
            if (!AdjustTokenPrivileges(token, false, ref state, 0, IntPtr.Zero, IntPtr.Zero)) return Marshal.GetLastWin32Error();
            return Marshal.GetLastWin32Error(); // ERROR_NOT_ALL_ASSIGNED (1300) when the right is absent
        }
        finally { CloseHandle(token); }
    }

    // ---- hives -----------------------------------------------------------------------------------------------

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegLoadKeyW")]
    private static extern int RegLoadKey(IntPtr key, string subKey, string file);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegUnLoadKeyW")]
    private static extern int RegUnLoadKey(IntPtr key, string subKey);

    public static int LoadHive(string keyName, string file) { return RegLoadKey(HKEY_LOCAL_MACHINE, keyName, file); }
    public static int UnloadHive(string keyName) { return RegUnLoadKey(HKEY_LOCAL_MACHINE, keyName); }

    public static string Describe(int code) { return new Win32Exception(code).Message; }

    // ---- backup/restore registry access ------------------------------------------------------------------

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegCreateKeyExW")]
    private static extern int RegCreateKeyEx(IntPtr key, string subKey, int reserved, string cls, int options,
        int desired, IntPtr security, out IntPtr result, out int disposition);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegOpenKeyExW")]
    private static extern int RegOpenKeyEx(IntPtr key, string subKey, int options, int desired, out IntPtr result);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegSetValueExW")]
    private static extern int RegSetValueEx(IntPtr key, string name, int reserved, int type, byte[] data, int size);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegQueryValueExW")]
    private static extern int RegQueryValueEx(IntPtr key, string name, IntPtr reserved, out int type, byte[] data, ref int size);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegDeleteValueW")]
    private static extern int RegDeleteValue(IntPtr key, string name);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegDeleteTreeW")]
    private static extern int RegDeleteTree(IntPtr key, string subKey);
    [DllImport("advapi32.dll")]
    private static extern int RegCloseKey(IntPtr key);

    // Every call first OPENS the already-loaded image hive root (HKLM\<hive>) and only
    // then creates/opens beneath it, so nothing can ever be created at the HKLM root.
    private static int OpenHive(string hive, out IntPtr root)
    {
        root = IntPtr.Zero;
        if (string.IsNullOrEmpty(hive) || hive.IndexOf('\\') >= 0) return 87; // ERROR_INVALID_PARAMETER
        return RegOpenKeyEx(HKEY_LOCAL_MACHINE, hive, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, out root);
    }

    // Returns 0 only when the value was written AND read back with the same type and bytes.
    public static int SetValue(string hive, string subKey, string name, int type, byte[] data)
    {
        IntPtr root;
        int code = OpenHive(hive, out root);
        if (code != 0) return code;
        try
        {
            IntPtr key; int disposition;
            code = RegCreateKeyEx(root, subKey, 0, null, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, IntPtr.Zero, out key, out disposition);
            if (code != 0) return code;
            try
            {
                code = RegSetValueEx(key, name, 0, type, data, data.Length);
                if (code != 0) return code;
                int readType; int size = data.Length + 8; byte[] read = new byte[size];
                code = RegQueryValueEx(key, name, IntPtr.Zero, out readType, read, ref size);
                if (code != 0) return code;
                if (readType != type || size != data.Length) return 1359; // ERROR_INTERNAL_ERROR: readback differs
                for (int i = 0; i < size; i++) if (read[i] != data[i]) return 1359;
                return 0;
            }
            finally { RegCloseKey(key); }
        }
        finally { RegCloseKey(root); }
    }

    public static int DeleteValue(string hive, string subKey, string name)
    {
        IntPtr root;
        int code = OpenHive(hive, out root);
        if (code != 0) return code;
        try
        {
            IntPtr key;
            code = RegOpenKeyEx(root, subKey, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, out key);
            if (code != 0) return code;
            try { return RegDeleteValue(key, name); } finally { RegCloseKey(key); }
        }
        finally { RegCloseKey(root); }
    }

    // Deletes subKey (relative to the hive root) and everything beneath it.
    public static int DeleteKeyTree(string hive, string subKey)
    {
        if (string.IsNullOrEmpty(subKey)) return 87;
        IntPtr root;
        int code = OpenHive(hive, out root);
        if (code != 0) return code;
        try { return RegDeleteTree(root, subKey) == 0 ? 0 : RegDeleteTreeFallback(root, subKey); }
        finally { RegCloseKey(root); }
    }

    // RegDeleteTree re-opens children with normal access checks; retry with an
    // explicit backup/restore walk so protected image subkeys can still be removed.
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegEnumKeyExW")]
    private static extern int RegEnumKeyEx(IntPtr key, int index, StringBuilder name, ref int nameLength,
        IntPtr reserved, IntPtr cls, IntPtr clsLength, IntPtr lastWrite);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegDeleteKeyW")]
    private static extern int RegDeleteKey(IntPtr key, string subKey);

    [DllImport("advapi32.dll")]
    private static extern int RegSetKeySecurity(IntPtr key, int information, byte[] descriptor);

    private static int RegDeleteTreeFallback(IntPtr parent, string subKey)
    {
        IntPtr key;
        int code = RegOpenKeyEx(parent, subKey, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, out key);
        if (code == 2) return 0;
        if (code != 0) return code;
        try
        {
            // Only keys that are about to be deleted get this DACL, so no ACL change survives.
            System.Security.AccessControl.RawSecurityDescriptor dacl =
                new System.Security.AccessControl.RawSecurityDescriptor("D:(A;CI;KA;;;BA)");
            byte[] binary = new byte[dacl.BinaryLength];
            dacl.GetBinaryForm(binary, 0);
            code = RegSetKeySecurity(key, 4, binary);
            if (code != 0) return code;
            while (true)
            {
                StringBuilder name = new StringBuilder(512); int length = name.Capacity;
                code = RegEnumKeyEx(key, 0, name, ref length, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                if (code == 259) break; // ERROR_NO_MORE_ITEMS
                if (code != 0) return code;
                code = RegDeleteTreeFallback(key, name.ToString());
                if (code != 0) return code;
            }
        }
        finally { RegCloseKey(key); }
        return RegDeleteKey(parent, subKey);
    }

    // ---- ACL-preserving deletion -------------------------------------------------------------------------

    // WIN32_FIND_DATAW: FILETIME is two 4-byte-aligned DWORDs, so it is spelled out
    // instead of declared as long (which would be 8-byte aligned and shift every field).
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct FindData
    {
        public uint Attributes;
        public uint CreatedLow; public uint CreatedHigh; public uint AccessedLow; public uint AccessedHigh;
        public uint WrittenLow; public uint WrittenHigh;
        public uint SizeHigh; public uint SizeLow; public uint Reserved0; public uint Reserved1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string AlternateName;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateFileW")]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security,
        uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int infoClass, ref uint info, int size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "GetFileAttributesW")]
    private static extern uint GetFileAttributes(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "FindFirstFileExW")]
    private static extern IntPtr FindFirstFileEx(string path, int level, out FindData data, int search, IntPtr filter, int flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "FindNextFileW")]
    private static extern bool FindNextFile(IntPtr find, out FindData data);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FindClose(IntPtr find);

    private static string Extended(string path)
    {
        string full = Path.GetFullPath(path);
        if (full.StartsWith(@"\\?\", StringComparison.Ordinal)) return full;
        if (full.StartsWith(@"\\", StringComparison.Ordinal)) throw new InvalidDataException("Network paths are not image paths: " + path);
        return @"\\?\" + full;
    }

    public static bool Exists(string path)
    {
        return GetFileAttributes(Extended(path)) != 0xFFFFFFFF;
    }

    // Deletes path (file or folder tree) inside root. Returns the number of entries deleted.
    // Throws Win32Exception naming the first entry that could not be deleted.
    public static long DeleteTree(string path, string root)
    {
        string full = Path.GetFullPath(path).TrimEnd('\\');
        string owner = Path.GetFullPath(root).TrimEnd('\\') + "\\";
        if (!full.StartsWith(owner, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Refusing to delete outside the image mount: " + path);
        string target = Extended(full);
        uint attributes = GetFileAttributes(target);
        if (attributes == 0xFFFFFFFF)
        {
            int missing = Marshal.GetLastWin32Error();
            if (missing == 2 || missing == 3) return 0;
            throw new Win32Exception(missing, "Cannot inspect " + full);
        }
        long count = 0;
        Delete(target, attributes, ref count);
        return count;
    }

    private static void Delete(string path, uint attributes, ref long count)
    {
        bool directory = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        bool link = (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
        if (directory && !link)
        {
            List<KeyValuePair<string, uint>> children = new List<KeyValuePair<string, uint>>();
            FindData data;
            IntPtr find = FindFirstFileEx(path + @"\*", 1, out data, 0, IntPtr.Zero, 2);
            if (find == new IntPtr(-1))
            {
                int error = Marshal.GetLastWin32Error();
                if (error != 2 && error != 18) throw new Win32Exception(error, "Cannot list " + path);
            }
            else
            {
                try
                {
                    do
                    {
                        if (data.Name == "." || data.Name == "..") continue;
                        children.Add(new KeyValuePair<string, uint>(path + "\\" + data.Name, data.Attributes));
                    } while (FindNextFile(find, out data));
                }
                finally { FindClose(find); }
            }
            foreach (KeyValuePair<string, uint> child in children) Delete(child.Key, child.Value, ref count);
        }
        using (SafeFileHandle handle = CreateFile(path, DELETE | FILE_READ_ATTRIBUTES, SHARE_ALL, IntPtr.Zero, OPEN_EXISTING,
                   FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero))
        {
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open for deletion: " + path);
            uint flags = DISPOSITION_FLAGS;
            if (!SetFileInformationByHandle(handle, FileDispositionInfoEx, ref flags, sizeof(uint)))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot delete: " + path);
        }
        count++;
    }
}
