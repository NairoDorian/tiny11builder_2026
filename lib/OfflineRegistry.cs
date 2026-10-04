using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

// Offreg operates on file-backed data in memory, outside the active registry.
// Load only the Windows copy; never resolve a DLL from the image or work folder.
public static class Tiny11OfflineRegistry
{
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll")]
    public static extern uint ORCreateHive(out IntPtr hive);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll", CharSet = CharSet.Unicode)]
    public static extern uint OROpenHive(string file, out IntPtr hive);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll", CharSet = CharSet.Unicode)]
    public static extern uint ORCreateKey(IntPtr hive, string path, string cls, uint options,
        IntPtr security, out IntPtr key, out uint disposition);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll", CharSet = CharSet.Unicode)]
    public static extern uint ORSetValue(IntPtr key, string name, uint type, byte[] data, uint count);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll", CharSet = CharSet.Unicode)]
    public static extern uint ORGetValue(IntPtr key, string path, string name, out uint type,
        byte[] data, ref uint count);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll", CharSet = CharSet.Unicode)]
    public static extern uint ORSaveHive(IntPtr hive, string file, uint major, uint minor);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll")]
    public static extern uint ORCloseHive(IntPtr hive);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("offreg.dll")]
    public static extern uint ORCloseKey(IntPtr key);

    public static void Check(uint result, string operation)
    {
        if (result != 0) throw new Win32Exception((int)result, operation + ": " + new Win32Exception((int)result).Message);
    }
}
