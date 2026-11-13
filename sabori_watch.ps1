# ============================================================
# sabori_watch (Windows PowerShell)
# 前面のウィンドウを監視して、対象アプリ／サイトを連続で
# 使い続けたら警告ウィンドウを出す。完全オフライン動作。
#
# 使い方: このファイルを右クリック -> PowerShellで実行
#         止め方: コンソールで Ctrl+C（隠して起動した場合は
#         タスクマネージャーから powershell を終了）
# ============================================================

# ---------------- 設定（ここを編集） ----------------
# ProcessNames : 対象プロセス名（.exe は付けない）
# TitleKeywords: ウィンドウタイトルに含まれていたら対象にする文字列
#                ブラウザで開く YouTube / X はこちらで判定する
#                アプリ単体で監視したいときは空 @() にする
# LimitMinutes : 連続使用の上限（分）
# Message      : 警告画面に出す文
$Rules = @(
    @{ ProcessNames = @("chrome", "msedge", "firefox"); TitleKeywords = @("YouTube");   LimitMinutes = 5; Message = "原稿に戻りましょう" },
    @{ ProcessNames = @("chrome", "msedge", "firefox"); TitleKeywords = @("/ X");       LimitMinutes = 5; Message = "原稿に戻りましょう" }
    # 例：Discordアプリ自体を10分で警告（タイトル判定なし）
    # @{ ProcessNames = @("Discord"); TitleKeywords = @(); LimitMinutes = 10; Message = "Discordを10分使っています。" }
)

$PollSeconds = 5   # チェック間隔（秒）
# ----------------------------------------------------

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Fg {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ForegroundInfo {
    $h = [Win32Fg]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return $null }
    $sb = New-Object System.Text.StringBuilder 512
    [void][Win32Fg]::GetWindowText($h, $sb, $sb.Capacity)
    $procId = [uint32]0
    [void][Win32Fg]::GetWindowThreadProcessId($h, [ref]$procId)
    $procName = ""
    try { $procName = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
    return @{ Process = $procName; Title = $sb.ToString() }
}

function Test-RuleMatch($rule, $fg) {
    if ($null -eq $fg) { return $false }
    if ($rule.ProcessNames.Count -gt 0 -and -not ($rule.ProcessNames -contains $fg.Process)) { return $false }
    if ($rule.TitleKeywords.Count -gt 0) {
        $hit = $false
        foreach ($kw in $rule.TitleKeywords) {
            if ($fg.Title -like "*$kw*") { $hit = $true; break }
        }
        if (-not $hit) { return $false }
    }
    return $true
}

function Show-Warning([string]$message) {
    [System.Media.SystemSounds]::Exclamation.Play()

    # 画面中央に、画面の1/4サイズ（縦横それぞれ半分）で表示
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size = New-Object System.Drawing.Size([int]($screen.Width / 2), [int]($screen.Height / 2))
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $form.KeyPreview = $true

    # 画面外をクリック（＝ウィンドウが非アクティブ化）したら閉じる。
    # ただし表示直後の誤作動を防ぐため、800ミリ秒経ってから有効にする
    $script:warningShownAt = Get-Date
    $form.Add_Deactivate({
        if (((Get-Date) - $script:warningShownAt).TotalMilliseconds -gt 800) { $form.Close() }
    })

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.RowCount = 2
    $layout.ColumnCount = 1
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 78)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 22)))
    $form.Controls.Add($layout)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $message
    $label.ForeColor = [System.Drawing.Color]::White
    $label.Font = New-Object System.Drawing.Font("Yu Gothic UI", 20, [System.Drawing.FontStyle]::Bold)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.Controls.Add($label, 0, 0)

    $button = New-Object System.Windows.Forms.Button
    $button.Text = "閉じる（タイマーをリセット）"
    $button.Font = New-Object System.Drawing.Font("Yu Gothic UI", 12)
    $button.Size = New-Object System.Drawing.Size(300, 48)
    $button.Anchor = [System.Windows.Forms.AnchorStyles]::None
    $button.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 68)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.Add_Click({ $form.Close() })
    $layout.Controls.Add($button, 0, 1)

    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    $form.Dispose()
}

# ルールごとの連続使用の開始時刻
$startTimes = @{}
for ($i = 0; $i -lt $Rules.Count; $i++) { $startTimes[$i] = $null }

Write-Host "監視を開始しました。終了は Ctrl+C"
Write-Host ("対象ルール: {0} 件 / チェック間隔: {1} 秒" -f $Rules.Count, $PollSeconds)

while ($true) {
    $fg = Get-ForegroundInfo
    $now = Get-Date
    for ($i = 0; $i -lt $Rules.Count; $i++) {
        $rule = $Rules[$i]
        if (Test-RuleMatch $rule $fg) {
            if ($null -eq $startTimes[$i]) {
                $startTimes[$i] = $now
                Write-Host ("[{0}] 計測開始: {1} ({2})" -f $now.ToString("HH:mm:ss"), $fg.Process, $fg.Title)
            }
            $elapsed = ($now - $startTimes[$i]).TotalMinutes
            if ($elapsed -ge $rule.LimitMinutes) {
                Write-Host ("[{0}] 警告表示: ルール {1}（{2} 分経過）" -f $now.ToString("HH:mm:ss"), ($i + 1), [math]::Round($elapsed, 1))
                Show-Warning $rule.Message
                $startTimes[$i] = $null   # 警告を閉じたらタイマーリセット
            }
        } else {
            if ($null -ne $startTimes[$i]) {
                Write-Host ("[{0}] 対象から離れたためリセット: ルール {1}" -f $now.ToString("HH:mm:ss"), ($i + 1))
                $startTimes[$i] = $null
            }
        }
    }
    Start-Sleep -Seconds $PollSeconds
}
