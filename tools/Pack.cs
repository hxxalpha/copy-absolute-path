// SPDX-License-Identifier: MIT
// Uses the Windows packaging API; no external packaging SDK is required.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
[StructLayout(LayoutKind.Sequential)]
struct PackageSettings { public int ForceZip32; public IntPtr HashMethod; }
[ComImport, Guid("beb94909-e451-438b-b5a7-d79e767b75d8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAppxFactory {
    [PreserveSig] int CreatePackageWriter(IStream output, ref PackageSettings settings, out IAppxPackageWriter writer);
}
[ComImport, Guid("9099e33b-246f-41e4-881a-008eb613f858"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAppxPackageWriter {
    [PreserveSig] int AddPayloadFile([MarshalAs(UnmanagedType.LPWStr)] string name,
        [MarshalAs(UnmanagedType.LPWStr)] string type, uint compression, IStream input);
    [PreserveSig] int Close(IStream manifest);
}
class Pack {
    [DllImport("shlwapi.dll", CharSet=CharSet.Unicode)]
    static extern int SHCreateStreamOnFileEx(string path, uint mode, uint attributes,
        [MarshalAs(UnmanagedType.Bool)] bool create, IntPtr template, out IStream stream);
    [DllImport("urlmon.dll", CharSet=CharSet.Unicode)]
    static extern int CreateUri(string uri, uint flags, IntPtr reserved, out IntPtr result);
    static void Check(int code) { Marshal.ThrowExceptionForHR(code); }
    static IStream Input(string path) {
        IStream stream;
        Check(SHCreateStreamOnFileEx(path, 0x10, 0, false, IntPtr.Zero, out stream));
        return stream;
    }
    static int Main(string[] args) {
        IStream output = null;
        IAppxPackageWriter writer = null;
        IAppxFactory factory = null;
        IntPtr uri = IntPtr.Zero;
        try {
            if (args.Length != 2) throw new ArgumentException("Usage: Pack.exe STAGE OUTPUT.msix");
            string stage = Path.GetFullPath(args[0]).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            Check(SHCreateStreamOnFileEx(args[1], 0x1011, 0, true, IntPtr.Zero, out output));
            Check(CreateUri("http://www.w3.org/2001/04/xmlenc#sha256", 0x100, IntPtr.Zero, out uri));
            var settings = new PackageSettings { ForceZip32 = 1, HashMethod = uri };
            factory = (IAppxFactory)Activator.CreateInstance(
                Type.GetTypeFromCLSID(new Guid("5842a140-ff9f-4166-8f5c-62f5b7b0c781")));
            Check(factory.CreatePackageWriter(output, ref settings, out writer));
            foreach (string path in Directory.GetFiles(stage, "*", SearchOption.AllDirectories)) {
                string relative = path.Substring(stage.Length);
                if (relative.Equals("AppxManifest.xml", StringComparison.OrdinalIgnoreCase)) continue;
                IStream input = Input(path);
                string type = path.EndsWith(".png", StringComparison.OrdinalIgnoreCase) ? "image/png" : "application/octet-stream";
                try { Check(writer.AddPayloadFile(relative, type, 1, input)); }
                finally { Marshal.FinalReleaseComObject(input); }
            }
            IStream manifest = Input(Path.Combine(stage, "AppxManifest.xml"));
            try { Check(writer.Close(manifest)); }
            finally { Marshal.FinalReleaseComObject(manifest); }
            Console.WriteLine("Created package: " + Path.GetFileName(args[1]));
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally {
            if (writer != null) Marshal.FinalReleaseComObject(writer);
            if (factory != null) Marshal.FinalReleaseComObject(factory);
            if (output != null) Marshal.FinalReleaseComObject(output);
            if (uri != IntPtr.Zero) Marshal.Release(uri);
        }
    }
}
