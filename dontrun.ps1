
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$url = 'https://hackaday.com/wp-content/uploads/2023/02/TWC_Local_On_The_8s__Tornado_Warning_with_EAS_Oct_14_2016_.webp?w=400'
$dir = Join-Path $env:TEMP 'EASViewer'
$file = Join-Path $dir 'warning.webp'

New-Item -ItemType Directory -Path $dir -Force | Out-Null

$source = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class KeyboardBlocker
{
    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);
    private static HookProc callback = HookCallback;
    private static IntPtr hook = IntPtr.Zero;
    private static bool enabled = false;

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && enabled)
        {
            KBDLLHOOKSTRUCT key =
                Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);

            if (key.vkCode == 0x5B || key.vkCode == 0x5C)
                return (IntPtr)1;
        }

        return CallNextHookEx(hook, nCode, wParam, lParam);
    }

    public static void Start()
    {
        if (hook != IntPtr.Zero) return;

        using (Process process = Process.GetCurrentProcess())
        using (ProcessModule module = process.MainModule)
        {
            hook = SetWindowsHookEx(
                13, callback, GetModuleHandle(module.ModuleName), 0);
        }

        enabled = hook != IntPtr.Zero;
    }

    public static void Stop()
    {
        enabled = false;

        if (hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(hook);
            hook = IntPtr.Zero;
        }
    }
}
'@

Add-Type -TypeDefinition $source

$form = $null
$picture = $null
$timer = $null
$allowExit = $false

try {
    Invoke-WebRequest -Uri $url -OutFile $file -ErrorAction Stop

    $form = New-Object Windows.Forms.Form
    $form.Text = 'Viewer - Press X to exit'
    $form.FormBorderStyle = 'None'
    $form.WindowState = 'Normal'
    $form.StartPosition = 'Manual'
    $form.Bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $form.TopMost = $true
    $form.BackColor = [Drawing.Color]::Black
    $form.KeyPreview = $true
    $form.ShowInTaskbar = $false

    $picture = New-Object Windows.Forms.PictureBox
    $picture.Location = New-Object Drawing.Point(0, 0)
    $picture.BackColor = [Drawing.Color]::Black
    $picture.SizeMode = 'StretchImage'
    $picture.Image = [Drawing.Image]::FromFile($file)

    $form.Controls.Add($picture)

    $form.Add_Shown({
        $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $form.Bounds = $bounds
        $picture.Left = 0
        $picture.Top = 0
        $picture.Width = $bounds.Width
        $picture.Height = [int]($bounds.Height * 8 / 7)
        $form.TopMost = $true
        $form.Activate()
        [KeyboardBlocker]::Start()
    })

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 500
    $timer.Add_Tick({
        if ($form -and -not $form.IsDisposed -and -not $allowExit) {
            $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds

            if ($form.Bounds -ne $bounds) {
                $form.Bounds = $bounds
            }

            if (-not $form.TopMost) {
                $form.TopMost = $true
            }
        }
    })
    $timer.Start()

    $form.Add_KeyDown({
        if ($_.KeyCode -eq [Windows.Forms.Keys]::X) {
            $allowExit = $true
            $form.Close()
        }

        $_.Handled = $true
        $_.SuppressKeyPress = $true
    })

    $form.Add_FormClosing({
        if (-not $allowExit) {
            $_.Cancel = $true
        }
        else {
            [KeyboardBlocker]::Stop()

            if ($timer) {
                $timer.Stop()
            }

            if ($picture.Image) {
                $picture.Image.Dispose()
                $picture.Image = $null
            }
        }
    })

    [void]$form.ShowDialog()
}
catch {
    [KeyboardBlocker]::Stop()

    [Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        'Viewer error'
    ) | Out-Null
}
finally {
    [KeyboardBlocker]::Stop()

    if ($timer) { $timer.Dispose() }
    if ($form) { $form.Dispose() }

    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
}
