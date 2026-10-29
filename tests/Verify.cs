// SPDX-License-Identifier: MIT
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComImport, Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IClassFactory {
    [PreserveSig] int CreateInstance(IntPtr outer, ref Guid iid, out IntPtr instance);
    [PreserveSig] int LockServer([MarshalAs(UnmanagedType.Bool)] bool value);
}
[ComImport, Guid("A08CE4D0-FA25-44AB-B57C-C7B1C323E0B9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IExplorerCommand {
    [PreserveSig] int GetTitle(IntPtr items, out IntPtr title);
    [PreserveSig] int GetIcon(IntPtr items, out IntPtr icon);
    [PreserveSig] int GetToolTip(IntPtr items, out IntPtr tooltip);
    [PreserveSig] int GetCanonicalName(out Guid name);
    [PreserveSig] int GetState(IntPtr items, [MarshalAs(UnmanagedType.Bool)] bool slow, out uint state);
    [PreserveSig] int Invoke(IntPtr items, IntPtr context);
    [PreserveSig] int GetFlags(out uint flags);
    [PreserveSig] int EnumSubCommands(out IntPtr commands);
}
class Verify {
    static Guid classId = new Guid("CE06539D-2B11-4F45-8C71-622B8A73AD38");
    static Guid commandId = new Guid("A08CE4D0-FA25-44AB-B57C-C7B1C323E0B9");
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int ClassObject(ref Guid clsid, ref Guid iid, out IntPtr result);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int BuildText(IntPtr items, out IntPtr text);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int CanUnload();
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi)]
    static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
    [DllImport("ole32.dll")]
    static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid, out IntPtr instance);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    static extern int SHParseDisplayName(string path, IntPtr bind, out IntPtr pidl, uint attributes, out uint result);
    [DllImport("shell32.dll")]
    static extern int SHCreateShellItemArrayFromIDLists(uint count, [In] IntPtr[] pidls, out IntPtr array);
    static void Check(int status) { Marshal.ThrowExceptionForHR(status); }
    static void Assert(bool value, string message) { if (!value) throw new Exception(message); }
    static T Export<T>(IntPtr module, string name) where T : class {
        IntPtr pointer = GetProcAddress(module, name);
        Assert(pointer != IntPtr.Zero, "Missing export: " + name);
        return Marshal.GetDelegateForFunctionPointer(pointer, typeof(T)) as T;
    }
    static IExplorerCommand Create(IntPtr module, bool registered) {
        IntPtr pointer;
        if (registered) Check(CoCreateInstance(ref classId, IntPtr.Zero, 4, ref commandId, out pointer));
        else {
            var getFactory = Export<ClassObject>(module, "DllGetClassObject");
            Guid factoryId = new Guid("00000001-0000-0000-C000-000000000046");
            IntPtr factoryPointer;
            Guid wrongClass = Guid.NewGuid();
            Assert(getFactory(ref wrongClass, ref factoryId, out factoryPointer) < 0 && factoryPointer == IntPtr.Zero,
                "Unknown COM class must be rejected.");
            Check(getFactory(ref classId, ref factoryId, out factoryPointer));
            var factory = (IClassFactory)Marshal.GetObjectForIUnknown(factoryPointer);
            Marshal.Release(factoryPointer);
            try {
                Guid wrongInterface = Guid.NewGuid();
                Assert(factory.CreateInstance(IntPtr.Zero, ref wrongInterface, out pointer) < 0 && pointer == IntPtr.Zero,
                    "Unknown interface must be rejected.");
                Check(factory.CreateInstance(IntPtr.Zero, ref commandId, out pointer));
            } finally { Marshal.FinalReleaseComObject(factory); }
        }
        var command = (IExplorerCommand)Marshal.GetObjectForIUnknown(pointer);
        Marshal.Release(pointer);
        return command;
    }
    static IntPtr Items(string[] paths) {
        IntPtr[] pidls = new IntPtr[paths.Length];
        try {
            for (int index = 0; index < paths.Length; index++) {
                uint ignored;
                Check(SHParseDisplayName(paths[index], IntPtr.Zero, out pidls[index], 0, out ignored));
            }
            IntPtr array;
            Check(SHCreateShellItemArrayFromIDLists((uint)pidls.Length, pidls, out array));
            return array;
        } finally { foreach (var pidl in pidls) if (pidl != IntPtr.Zero) Marshal.FreeCoTaskMem(pidl); }
    }
    static void RunCase(IExplorerCommand command, BuildText build, string label, string[] paths, bool clipboard) {
        IntPtr array = Items(paths);
        try {
            uint state;
            Check(command.GetState(array, false, out state));
            Assert(state == 0, "Selection must be enabled: " + label);
            IntPtr text;
            Check(build(array, out text));
            string actual = Marshal.PtrToStringUni(text);
            Marshal.FreeCoTaskMem(text);
            Assert(actual == string.Join("\r\n", paths), "Incorrect selection text: " + label);
            if (clipboard) {
                Check(command.Invoke(array, IntPtr.Zero));
                Assert(Clipboard.GetText(TextDataFormat.UnicodeText) == actual, "Incorrect clipboard text: " + label);
            }
            Console.WriteLine("PASS " + label);
        } finally { Marshal.Release(array); }
    }
    [STAThread]
    static int Main(string[] args) {
        IntPtr production = IntPtr.Zero, testing = IntPtr.Zero;
        IExplorerCommand command = null;
        bool useClipboard = Array.IndexOf(args, "--clipboard") >= 0;
        bool registered = Array.IndexOf(args, "--registered") >= 0;
        bool changedClipboard = false, clipboardWasEmpty = false;
        DataObject backup = new DataObject();
        string directory = null;
        string first = null, second = null;
        try {
            if (args.Length < 1) throw new ArgumentException("Usage: Verify.exe BUILD_DIR [--clipboard] [--registered]");
            string buildDirectory = Path.GetFullPath(args[0]);
            production = LoadLibraryEx(Path.Combine(buildDirectory, "CopyPathCommand.dll"), IntPtr.Zero, 8);
            testing = LoadLibraryEx(Path.Combine(buildDirectory, "CopyPathCommand.Test.dll"), IntPtr.Zero, 8);
            Assert(production != IntPtr.Zero && testing != IntPtr.Zero, "Cannot load native DLLs.");
            Assert(GetProcAddress(production, "CopyPathTestBuildSelectionText") == IntPtr.Zero, "Production DLL must not export test hooks.");
            var build = Export<BuildText>(testing, "CopyPathTestBuildSelectionText");
            command = Create(production, registered);
            IntPtr title;
            Check(command.GetTitle(IntPtr.Zero, out title));
            string label = Marshal.PtrToStringUni(title);
            Marshal.FreeCoTaskMem(title);
            Assert(label == "复制绝对路径" || label == "Copy absolute path", "Incorrect localized menu title.");
            Guid canonical;
            Check(command.GetCanonicalName(out canonical));
            Assert(canonical == classId, "Incorrect canonical command ID.");
            uint state;
            Check(command.GetState(IntPtr.Zero, false, out state));
            Assert(state == 2, "Empty selection must be hidden.");
            Assert(command.Invoke(IntPtr.Zero, IntPtr.Zero) < 0, "Invalid selection must fail.");
            IntPtr invalidText;
            Assert(build(IntPtr.Zero, out invalidText) < 0 && invalidText == IntPtr.Zero, "Invalid selection must not return text.");
            Console.WriteLine("PASS COM activation, localization, invalid selection and production exports");
            if (useClipboard) {
                var original = Clipboard.GetDataObject();
                clipboardWasEmpty = original == null || original.GetFormats(false).Length == 0;
                if (!clipboardWasEmpty) foreach (string format in original.GetFormats(false)) {
                    object value = original.GetData(format, false);
                    if (value == null && format == "EnterpriseDataProtectionId") continue;
                    Assert(value != null, "Cannot preserve clipboard format: " + format);
                    var stream = value as MemoryStream;
                    if (stream != null) value = new MemoryStream(stream.ToArray());
                    backup.SetData(format, false, value);
                }
                changedClipboard = true;
            }
            directory = Path.Combine(buildDirectory, "test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            first = Path.Combine(directory, "中文 空格 ' & $ (路径) 😀.txt");
            second = Path.Combine(directory, "plain.txt");
            File.WriteAllText(first, "synthetic test fixture");
            File.WriteAllText(second, "synthetic test fixture");
            RunCase(command, build, "Unicode, spaces, punctuation and emoji", new[] { first }, useClipboard);
            RunCase(command, build, "folder", new[] { directory }, useClipboard);
            RunCase(command, build, "multiple files in selection order", new[] { first, second }, useClipboard);
            RunCase(command, build, "mixed folder and file", new[] { directory, first }, useClipboard);
            RunCase(command, build, "drive root", new[] { Path.GetPathRoot(directory) }, useClipboard);
            Marshal.FinalReleaseComObject(command);
            command = null;
            Assert(Export<CanUnload>(production, "DllCanUnloadNow")() == 0, "Native COM references were not released.");
            Console.WriteLine("PASS COM lifetime");
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally {
            if (changedClipboard) {
                if (clipboardWasEmpty) Clipboard.Clear();
                else Clipboard.SetDataObject(backup, true, 10, 50);
                Console.WriteLine("Original clipboard restored.");
            }
            if (command != null) Marshal.FinalReleaseComObject(command);
            if (production != IntPtr.Zero) FreeLibrary(production);
            if (testing != IntPtr.Zero) FreeLibrary(testing);
            if (first != null && File.Exists(first)) File.Delete(first);
            if (second != null && File.Exists(second)) File.Delete(second);
            if (directory != null && Directory.Exists(directory) && Directory.GetFileSystemEntries(directory).Length == 0)
                Directory.Delete(directory);
        }
    }
}
