/*
 * Patch Checkpoint Windows executable host.
 * Hosts the embedded application in Windows PowerShell 5.1 on the STA UI thread.
 * Resources are extracted to a new, owner/SYSTEM-only directory for the remote
 * script and diagnostic hashes. No execution policy, credentials or machine
 * settings are changed. Campaign settings live outside the temporary directory.
 */
using System;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("Patch Checkpoint")]
[assembly: AssemblyDescription("Windows OS/.NET patch and reboot verification")]
[assembly: AssemblyProduct("Patch Checkpoint")]
[assembly: AssemblyVersion("1.0.1.0")]
[assembly: AssemblyFileVersion("1.0.1.0")]

namespace PatchCheckpoint
{
    public static class Program
    {
        public static string RuntimeRoot { get; private set; }
        public static string SelfTestDataRoot { get; private set; }
        private static readonly string[] ResourceNames = {
            "Start-PatchCheckpoint.ps1", "Validation.Core.ps1", "Remote.Assessment.ps1",
            "UI.Theme.ps1", "UI.Commands.ps1", "Diagnostics.Export.ps1", "Computers.example.csv",
            "README.md", "USER-GUIDE.md", "TROUBLESHOOTING.md", "CHANGELOG.md", "SECURITY.md",
            "Executable.SmokeTest.ps1"
        };

        [STAThread]
        public static int Main(string[] args)
        {
            string report = null;
            bool selfTestRequested = false;
            try
            {
                bool demo = false;
                int timeout = 180, minimumUptime = 120;
                for (int i = 0; i < args.Length; i++)
                {
                    string option = args[i].ToLowerInvariant();
                    if (option == "-demo" || option == "--demo") demo = true;
                    else if (option == "--self-test" && i + 1 < args.Length)
                    {
                        selfTestRequested = true;
                        string requestedReport = Path.GetFullPath(args[++i]);
                        if (Path.GetExtension(requestedReport).ToLowerInvariant() != ".json" || File.Exists(requestedReport))
                            throw new ArgumentException("Self-test requires a new .json report filename.");
                        report = requestedReport;
                        SelfTestDataRoot = Path.Combine(Path.GetDirectoryName(report), "EXE-Data-" + Guid.NewGuid().ToString("N"));
                    }
                    else if (option == "-timeoutseconds" && i + 1 < args.Length)
                        timeout = ParseNumber(args[++i], 30, 900, "TimeoutSeconds");
                    else if (option == "-minimumuptimeseconds" && i + 1 < args.Length)
                        minimumUptime = ParseNumber(args[++i], 0, 1800, "MinimumUptimeSeconds");
                    else throw new ArgumentException("Supported options: -Demo, -TimeoutSeconds 30..900, -MinimumUptimeSeconds 0..1800.");
                }
                if (!Environment.Is64BitProcess) throw new InvalidOperationException("Use the x64 executable.");
                PrepareResources();
                return RunApplication(demo, timeout, minimumUptime, report);
            }
            catch (Exception error)
            {
                if (report != null)
                {
                    // Failure reporting must never overwrite a caller's file,
                    // including when output validation itself failed.
                    try
                    {
                        using (StreamWriter writer = new StreamWriter(new FileStream(report, FileMode.CreateNew, FileAccess.Write, FileShare.None)))
                            writer.Write("{\"Success\":false,\"Error\":\"" + JsonEscape(error.ToString()) + "\"}");
                    }
                    catch (IOException) { }
                    catch (UnauthorizedAccessException) { }
                }
                else if (!selfTestRequested) MessageBox.Show(error.Message, "Patch Checkpoint could not start", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            finally { CleanupResources(); }
        }

        private static int ParseNumber(string value, int minimum, int maximum, string name)
        {
            int result;
            if (!Int32.TryParse(value, out result) || result < minimum || result > maximum)
                throw new ArgumentException(name + " must be between " + minimum + " and " + maximum + ".");
            return result;
        }

        private static string JsonEscape(string value)
        {
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t");
        }

        private static void PrepareResources()
        {
            RuntimeRoot = Path.Combine(Path.GetTempPath(), "PatchCheckpoint-" + Guid.NewGuid().ToString("N"));
            if (Directory.Exists(RuntimeRoot)) throw new IOException("Runtime directory already exists.");
            DirectorySecurity security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            SecurityIdentifier user = WindowsIdentity.GetCurrent().User;
            security.SetOwner(user);
            InheritanceFlags inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            security.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
            Directory.CreateDirectory(RuntimeRoot, security);
            foreach (string name in ResourceNames)
            {
                using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("PatchCheckpoint." + name))
                {
                    if (input == null) throw new InvalidOperationException("Embedded resource is missing: " + name);
                    using (FileStream output = new FileStream(Path.Combine(RuntimeRoot, name), FileMode.CreateNew, FileAccess.Write, FileShare.None)) input.CopyTo(output);
                }
            }
        }

        private static int RunApplication(bool demo, int timeout, int minimumUptime, string report)
        {
            // Use the calling STA thread for the WinForms message loop. Workers
            // continue to use the application's existing bounded runspace pools.
            using (Runspace runspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault()))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    string source = File.ReadAllText(Path.Combine(RuntimeRoot, "Start-PatchCheckpoint.ps1"));
                    if (report != null)
                    {
                        runspace.SessionStateProxy.SetVariable("ExecutableTestReport", report);
                        shell.AddScript(File.ReadAllText(Path.Combine(RuntimeRoot, "Executable.SmokeTest.ps1"))).Invoke();
                        if (shell.HadErrors) throw new InvalidOperationException(shell.Streams.Error[0].ToString());
                        shell.Commands.Clear();
                        source = source.Replace("[Windows.Forms.Application]::Run($script:form)", "Invoke-ExecutableSmokeTest");
                        demo = true;
                    }
                    shell.AddScript(source).AddParameter("Demo", demo).AddParameter("TimeoutSeconds", timeout).AddParameter("MinimumUptimeSeconds", minimumUptime);
                    shell.Invoke();
                    if (shell.HadErrors) throw new InvalidOperationException(shell.Streams.Error[0].ToString());
                    if (report != null && !File.Exists(report)) throw new IOException("Self-test did not produce its result file.");
                }
            }
            return 0;
        }

        private static void CleanupResources()
        {
            if (String.IsNullOrEmpty(RuntimeRoot)) return;
            // Delete only our known files, never recurse into a computed path.
            foreach (string name in ResourceNames)
            {
                try { File.Delete(Path.Combine(RuntimeRoot, name)); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            try { if (Directory.Exists(RuntimeRoot)) Directory.Delete(RuntimeRoot, false); }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
