
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore

$bgUrl = 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRfCTHiGTGzMRwHma_X2xS3Khg7NBqlpMF934fzubkJNA&s=10'
$cartUrl = 'https://static.wikia.nocookie.net/southpark/images/c/c4/Eric-cartman.png/revision/latest/scale-to-width-down/250?cb=20180718082504'
$mp3Url = 'https://www.image2url.com/r2/default/audio/1792545663900-4cf6346a-d028-42ef-bce1-4ce5fdb0a7fe.mp3'
$dir = "$env:TEMP\CartmanScreen"
New-Item -ItemType Directory -Force $dir | Out-Null
$bgFile = "$dir\bg.jpg"
$cartFile = "$dir\cart.png"
$mp3File = "$dir\audio.mp3"

# Download in parallel
$jobs = @(
    Start-Job { Invoke-WebRequest $using:bgUrl -OutFile $using:bgFile }
    Start-Job { Invoke-WebRequest $using:cartUrl -OutFile $using:cartFile }
    Start-Job { Invoke-WebRequest $using:mp3Url -OutFile $using:mp3File }
)
$jobs | Wait-Job | Out-Null
$bad = $jobs | Where-Object { $_.State -ne 'Completed' }
$jobs | Receive-Job -ErrorAction SilentlyContinue | Out-Null
$jobs | Remove-Job -Force
if ($bad -or !(Test-Path $bgFile) -or !(Test-Path $cartFile)) {
    Write-Host "Download failed. Check the URLs or internet connection."
    return
}

# Master volume to 100% using Windows audio endpoint
try {
    $ws = New-Object -ComObject WScript.Shell
    # Windows master volume API is not built into WScript.Shell.
    # The audio player's own volume is set to 100% below.
} catch {}

$form = New-Object Windows.Forms.Form
$form.Text = 'Cartman - Press X to exit'
$form.FormBorderStyle = 'None'
$form.WindowState = 'Maximized'
$form.TopMost = $true
$form.BackColor = 'Black'
$form.KeyPreview = $true

$bg = New-Object Windows.Forms.PictureBox
$bg.Dock = 'Fill'
$bg.SizeMode = 'Zoom'
$bg.Image = [Drawing.Image]::FromFile($bgFile)
$form.Controls.Add($bg)

$cartImage = [Drawing.Image]::FromFile($cartFile)
$items = @()
$r = [Random]::new()

1..5 | ForEach-Object {
    $p = New-Object Windows.Forms.PictureBox
    $p.Size = [Drawing.Size]::new(125,125)
    $p.SizeMode = 'Zoom'
    $p.Image = $cartImage
    $p.Location = [Drawing.Point]::new(
        $r.Next(0,[Math]::Max(1,$form.Width-125)),
        $r.Next(0,[Math]::Max(1,$form.Height-125))
    )
    $form.Controls.Add($p)
    $p.BringToFront()
    $dx = $r.Next(4,10) * $(if($r.Next(2)){1}else{-1})
    $dy = $r.Next(4,10) * $(if($r.Next(2)){1}else{-1})
    $items += @{ C=$p; X=$dx; Y=$dy }
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 16
$timer.Add_Tick({
    foreach($i in $items) {
        $c=$i.C
        $x=$c.Left+$i.X
        $y=$c.Top+$i.Y
        if($x -le 0 -or $x+$c.Width -ge $form.ClientSize.Width){$i.X=-$i.X}
        if($y -le 0 -or $y+$c.Height -ge $form.ClientSize.Height){$i.Y=-$i.Y}
        $c.Left=[Math]::Max(0,[Math]::Min($form.ClientSize.Width-$c.Width,$x))
        $c.Top=[Math]::Max(0,[Math]::Min($form.ClientSize.Height-$c.Height,$y))
    }
})

$player = New-Object Windows.Media.MediaPlayer
$player.Volume = 1.0
$script:closing = $false

$form.Add_KeyDown({
    if($_.KeyCode -eq [Windows.Forms.Keys]::X){$form.Close()}
})
$form.Add_FormClosing({
    $script:closing=$true
    $timer.Stop()
    $player.Stop()
    $player.Close()
})
$player.add_MediaEnded({
    if(-not $script:closing){$player.Position=[TimeSpan]::Zero;$player.Play()}
})
$player.Open([Uri]$mp3File)

$form.Add_Shown({
    $timer.Start()
    $player.Play()
    $form.Activate()
})

try { [void]$form.ShowDialog() }
finally {
    $timer.Stop()
    $player.Stop()
    $player.Close()
    $bg.Image.Dispose()
    $cartImage.Dispose()
    $form.Dispose()
}
