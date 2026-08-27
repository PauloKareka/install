param(
    [string]$LocalPath
)
# ===================================================
# Instalador Multi-Modos Winget PRO - GUI (WPF)
# Versao: GUI v1
# ===================================================

# ---------------------------------------------------
# VERSAO DO SCRIPT (aparece na tela e no log, ajuda a
# identificar qual build gerou um relatorio especifico)
# ---------------------------------------------------
$ScriptVersion = 'v2.3 (2026-08-26)'

# ---------------------------------------------------
# CONFIGURACAO PARA USO VIA LINK (GITHUB)
# Edite estas duas linhas com o seu repositorio antes de publicar.
# ScriptUrl   = link "raw" deste proprio arquivo .ps1 no GitHub
# LogoBaseUrl = pasta "raw" onde estao os logos no GitHub
# ---------------------------------------------------
$ScriptUrl   = 'https://raw.githubusercontent.com/PauloKareka/install/main/Instalador_Winget_GUI_v1.ps1'
$LogoBaseUrl = 'https://raw.githubusercontent.com/PauloKareka/install/main/assets/'

# ---------------------------------------------------
# AUTO-ELEVACAO PARA ADMINISTRADOR
# ---------------------------------------------------
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    if ($LocalPath -and (Test-Path $LocalPath)) {
        # Rodando localmente via o lancador .bat (le o arquivo como UTF-8 e reexecuta)
        $EscapedPath = $LocalPath.Replace("'", "''")
        $Cmd = "`$c=[IO.File]::ReadAllText('$EscapedPath',[Text.Encoding]::UTF8); `$sb=[ScriptBlock]::Create(`$c); & `$sb -LocalPath '$EscapedPath'"
        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$Cmd`"" -Verb RunAs
    } elseif ($PSCommandPath) {
        # Rodando como arquivo .ps1 aberto diretamente (sem o lancador .bat)
        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        # Rodando via "irm URL | iex" (sem arquivo local) - relanca baixando de novo, ja elevado
        $ElevateCmd = "irm '$ScriptUrl' | iex"
        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$ElevateCmd`"" -Verb RunAs
    }
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ---------------------------------------------------
# SINCRONIZACAO DO RELOGIO DO SISTEMA
# ---------------------------------------------------
# Em Windows recem-instalado o relogio pode estar desatualizado antes da
# primeira sincronizacao, o que quebra validacao de certificado TLS (ex:
# erro "server certificate did not match" ao consultar a fonte msstore).
try {
    w32tm /resync /force *> $null
} catch {
    # Nao bloqueia o script se falhar
}

# ---------------------------------------------------
# INSTALACAO AUTOMATICA DO WINGET (SE NAO ESTIVER PRESENTE)
# ---------------------------------------------------
function Install-WingetIfMissing {
    $TempDir = Join-Path $env:TEMP 'WingetBootstrap'
    if (Test-Path $TempDir) { Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    try {
        Write-Host '[INFO] Consultando a release mais recente do winget...' -ForegroundColor Yellow
        $WingetRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing -ErrorAction Stop

        $WingetAsset = $WingetRelease.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
        $DepsAsset   = $WingetRelease.assets | Where-Object { $_.name -eq 'DesktopAppInstaller_Dependencies.zip' } | Select-Object -First 1

        if (-not $WingetAsset) { throw 'Nao foi possivel encontrar o instalador do winget na release mais recente.' }

        # As dependencias (VCLibs, UI.Xaml, WindowsAppRuntime) vem empacotadas pelo
        # proprio time do winget, ja na versao compativel com esta release especifica.
        if ($DepsAsset) {
            Write-Host '[INFO] Baixando dependencias oficiais do winget...' -ForegroundColor Yellow
            $DepsZipPath = Join-Path $TempDir 'Dependencies.zip'
            Invoke-WebRequest -Uri $DepsAsset.browser_download_url -OutFile $DepsZipPath -UseBasicParsing -ErrorAction Stop

            $DepsExtractPath = Join-Path $TempDir 'Dependencies'
            Expand-Archive -Path $DepsZipPath -DestinationPath $DepsExtractPath -Force

            $Arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
            $ArchFolder = Get-ChildItem -Path $DepsExtractPath -Directory -Recurse | Where-Object { $_.Name -eq $Arch } | Select-Object -First 1

            if ($ArchFolder) {
                Write-Host "[INFO] Instalando dependencias ($Arch)..." -ForegroundColor Yellow
                $DepFiles = @(Get-ChildItem -Path $ArchFolder.FullName -Filter '*.appx' -ErrorAction SilentlyContinue)
                $DepFiles += @(Get-ChildItem -Path $ArchFolder.FullName -Filter '*.msix' -ErrorAction SilentlyContinue)
                foreach ($Dep in $DepFiles) {
                    Add-AppxPackage -Path $Dep.FullName -ErrorAction SilentlyContinue
                }
            }
        }

        Write-Host '[INFO] Baixando o Winget (App Installer)...' -ForegroundColor Yellow
        $WingetPath = Join-Path $TempDir $WingetAsset.name
        Invoke-WebRequest -Uri $WingetAsset.browser_download_url -OutFile $WingetPath -UseBasicParsing -ErrorAction Stop

        Write-Host '[INFO] Instalando o Winget...' -ForegroundColor Yellow
        Add-AppxPackage -Path $WingetPath -ErrorAction Stop

        # Atualiza o PATH da sessao atual, ja que o winget acabou de ser registrado
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        Start-Sleep -Seconds 2

        return [bool](Get-Command winget -ErrorAction SilentlyContinue)
    } catch {
        Write-Host "[ERRO] Falha ao instalar o winget automaticamente: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ---------------------------------------------------
# VERIFICACAO DO WINGET
# ---------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '[INFO] Winget nao foi encontrado neste sistema.' -ForegroundColor Yellow
    Write-Host '[INFO] Tentando instalar o Winget automaticamente (App Installer)...' -ForegroundColor Yellow

    $WingetInstalled = Install-WingetIfMissing

    if (-not $WingetInstalled) {
        [System.Windows.MessageBox]::Show("Nao foi possivel instalar o Winget automaticamente (verifique tambem sua conexao com a internet).`n`nInstale manualmente pela Microsoft Store (busque por 'App Installer') ou baixe em https://aka.ms/getwinget, depois execute este script novamente.", 'Winget nao encontrado', 'OK', 'Error') | Out-Null
        exit
    }

    Write-Host '[OK] Winget instalado com sucesso!' -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# ---------------------------------------------------
# HABILITA O RECURSO NECESSARIO PARA --ignore-security-hash FUNCIONAR
# ---------------------------------------------------
# Sem isso, o winget recusa a flag --ignore-security-hash mesmo passada
# no comando (fica so mostrando a ajuda), exatamente como aconteceu antes.
try {
    winget settings --enable InstallerHashOverride *> $null
} catch {
    # Nao bloqueia o script se falhar - alguns pacotes so vao falhar por hash depois
}

# ---------------------------------------------------
# RESET DAS FONTES DO WINGET
# ---------------------------------------------------
# Corrige erros do tipo "server certificate did not match" ao consultar a
# fonte msstore, comuns em Windows recem-instalado (fonte com registro
# corrompido/desatualizado). O proprio winget sugere este comando quando
# esse erro acontece.
try {
    winget source reset --force *> $null
} catch {
    # Nao bloqueia o script se falhar
}

# ---------------------------------------------------
# VERIFICACAO DE CONEXAO COM A INTERNET
# ---------------------------------------------------
$Online = Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue
if (-not $Online) {
    $Online = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue
}
if (-not $Online) {
    [System.Windows.MessageBox]::Show('Nao foi possivel detectar conexao com a internet. Verifique sua rede/Wi-Fi e tente novamente.', 'Sem Internet', 'OK', 'Error') | Out-Null
    exit
}

# ---------------------------------------------------
# LOG (COM DATA/HORA)
# ---------------------------------------------------
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$LogFile   = Join-Path $env:USERPROFILE ("Desktop\Relatorio_Instalacao_Winget_GUI_" + $Timestamp + ".txt")

$Header = @"
===================================================
   RELATORIO DE INSTALACAO E ATUALIZACAO WINGET (GUI)
   Versao do Script: $ScriptVersion
   Data/Hora: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
===================================================

"@
Set-Content -Path $LogFile -Value $Header -Encoding utf8

# ---------------------------------------------------
# LISTAS DE PROGRAMAS
# ---------------------------------------------------
$Runtimes = @(
    [PSCustomObject]@{ Name = 'DirectX End-User Runtime'; Id = 'Microsoft.DirectX' }
    [PSCustomObject]@{ Name = 'Visual C++ Redistributable AIO'; Id = 'abbodi1406.vcredist' }
    [PSCustomObject]@{ Name = 'Java Runtime Environment (JRE)'; Id = 'Oracle.JavaRuntimeEnvironment' }
    [PSCustomObject]@{ Name = 'Microsoft Edge WebView2 Runtime'; Id = 'Microsoft.EdgeWebView2Runtime' }
    [PSCustomObject]@{ Name = '.NET Desktop Runtime 8 (LTS)'; Id = 'Microsoft.DotNet.DesktopRuntime.8' }
    [PSCustomObject]@{ Name = '.NET Desktop Runtime 10 (LTS mais recente)'; Id = 'Microsoft.DotNet.DesktopRuntime.10' }
)

$Principal = @(
    [PSCustomObject]@{ Name = 'Google Chrome'; Id = 'Google.Chrome' }
    [PSCustomObject]@{ Name = 'Brave Browser'; Id = 'Brave.Brave' }
    [PSCustomObject]@{ Name = '7-Zip'; Id = '7zip.7zip' }
    [PSCustomObject]@{ Name = 'Lightshot'; Id = 'Skillbrains.Lightshot' }
    [PSCustomObject]@{ Name = 'VLC Media Player'; Id = 'VideoLAN.VLC' }
    [PSCustomObject]@{ Name = 'WinRAR'; Id = 'RARLab.WinRAR' }
    [PSCustomObject]@{ Name = 'Sublime Text'; Id = 'SublimeHQ.SublimeText.4' }
    [PSCustomObject]@{ Name = 'Agent Ransack'; Id = 'Mythicsoft.AgentRansack' }
    [PSCustomObject]@{ Name = 'PDF-XChange Viewer'; Id = 'TrackerSoftware.PDF-XChangeViewer' }
    [PSCustomObject]@{ Name = 'AkelPad'; Id = 'AkelPad.AkelPad' }
    [PSCustomObject]@{ Name = 'Paint.NET'; Id = 'dotPDN.PaintDotNet' }
    [PSCustomObject]@{ Name = 'MPC-BE'; Id = 'MPC-BE.MPC-BE' }
    [PSCustomObject]@{ Name = 'qBittorrent'; Id = 'qBittorrent.qBittorrent' }
    [PSCustomObject]@{ Name = 'Everything'; Id = 'voidtools.Everything' }
    [PSCustomObject]@{ Name = 'ONLYOFFICE'; Id = 'ONLYOFFICE.DesktopEditors' }
    [PSCustomObject]@{ Name = 'Vivaldi'; Id = 'Vivaldi.Vivaldi' }
    [PSCustomObject]@{ Name = 'Opera'; Id = 'Opera.Opera' }
    [PSCustomObject]@{ Name = 'Opera GX'; Id = 'Opera.OperaGX' }
    [PSCustomObject]@{ Name = 'Winamp'; Id = 'Winamp.Winamp' }
    [PSCustomObject]@{ Name = 'K-Lite Codec Pack Full'; Id = 'CodecGuide.K-LiteCodecPack.Full' }
    [PSCustomObject]@{ Name = 'Microsoft Teams'; Id = 'Microsoft.Teams' }
    [PSCustomObject]@{ Name = 'IrfanView (Programa Principal)'; Id = 'IrfanSkiljan.IrfanView' }
)

$Opcionais = @(
    [PSCustomObject]@{ Name = 'Discord'; Id = 'Discord.Discord' }
    [PSCustomObject]@{ Name = 'Steam'; Id = 'Valve.Steam' }
    [PSCustomObject]@{ Name = 'Epic Games Launcher'; Id = 'EpicGames.EpicGamesLauncher' }
    [PSCustomObject]@{ Name = 'HiBit Uninstaller'; Id = 'HiBitSoftware.HiBitUninstaller' }
    [PSCustomObject]@{ Name = 'TreeSize Free'; Id = 'JAMSoftware.TreeSize.Free' }
    [PSCustomObject]@{ Name = 'Inkscape'; Id = 'Inkscape.Inkscape' }
    [PSCustomObject]@{ Name = 'FreeCAD'; Id = 'FreeCAD.FreeCAD' }
    [PSCustomObject]@{ Name = 'OrcaSlicer'; Id = 'SoftFever.OrcaSlicer' }
    [PSCustomObject]@{ Name = 'VidBee'; Id = 'Nexmoe.VidBee' }
    [PSCustomObject]@{ Name = 'Telegram Desktop'; Id = 'Telegram.TelegramDesktop' }
    [PSCustomObject]@{ Name = 'WhatsApp'; Id = '9NKSQGP7F2NH' }
    [PSCustomObject]@{ Name = 'CrystalDiskInfo'; Id = 'CrystalDewWorld.CrystalDiskInfo' }
    [PSCustomObject]@{ Name = 'Revo Uninstaller Free'; Id = 'RevoUninstaller.RevoUninstaller' }
    [PSCustomObject]@{ Name = 'Spotify'; Id = 'Spotify.Spotify' }
)

# ---------------------------------------------------
# XAML DA JANELA
# ---------------------------------------------------
[xml]$Xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Instalador Multi-Modos Winget PRO - GUI"
    Height="850" Width="960"
    WindowStartupLocation="CenterScreen"
    Background="#1E1E1E"
    FontFamily="Segoe UI">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="160"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" VerticalAlignment="Center">
                <TextBlock Name="TxtTitle" Text="Instalador Multi-Modos Winget PRO" FontSize="20" FontWeight="Bold" Foreground="White"/>
                <TextBlock Text="Marque os itens desejados em cada aba e clique em Instalar Selecionados" FontSize="12" Foreground="#AAAAAA"/>
                <TextBlock Name="TxtOsInfo" Text="Detectando sistema..." FontSize="12" Foreground="#6FA8DC" FontWeight="SemiBold"/>
            </StackPanel>
            <Image Grid.Column="1" Name="ImgOsLogo" Width="280" Margin="12,0,0,0"
                   HorizontalAlignment="Right" VerticalAlignment="Center" Stretch="Uniform"/>
        </Grid>

        <TabControl Grid.Row="1" Name="MainTabs" Background="#252526" BorderBrush="#3F3F46" Foreground="White">
            <TabItem Header="Runtimes / Base do Sistema">
                <DockPanel Margin="5">
                    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,8">
                        <Button Name="BtnSelAllRuntimes" Content="Selecionar Todos" Width="140" Height="28" Margin="0,0,8,0"/>
                        <Button Name="BtnClearRuntimes" Content="Limpar Selecao" Width="140" Height="28"/>
                    </StackPanel>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="PanelRuntimes" Orientation="Vertical"/>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>
            <TabItem Header="Lista Principal">
                <DockPanel Margin="5">
                    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,8">
                        <Button Name="BtnSelAllPrincipal" Content="Selecionar Todos" Width="140" Height="28" Margin="0,0,8,0"/>
                        <Button Name="BtnClearPrincipal" Content="Limpar Selecao" Width="140" Height="28"/>
                    </StackPanel>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="PanelPrincipal" Orientation="Vertical"/>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>
            <TabItem Header="Opcionais">
                <DockPanel Margin="5">
                    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,8">
                        <Button Name="BtnSelAllOpcionais" Content="Selecionar Todos" Width="140" Height="28" Margin="0,0,8,0"/>
                        <Button Name="BtnClearOpcionais" Content="Limpar Selecao" Width="140" Height="28"/>
                    </StackPanel>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="PanelOpcionais" Orientation="Vertical"/>
                    </ScrollViewer>
                </DockPanel>
            </TabItem>
            <TabItem Header="Ferramentas Extras">
                <StackPanel Margin="10">
                    <TextBlock Text="Estas ferramentas abrem em uma janela separada do PowerShell, direto da fonte oficial de cada projeto. Nenhuma acao e feita sem voce confirmar dentro da propria ferramenta."
                               Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,15" FontSize="12"/>
                    <Button Name="BtnToolMAS" Content="MAS - Activator" Height="36" Margin="0,0,0,8" HorizontalAlignment="Left" Width="320" FontSize="13"/>
                    <Button Name="BtnToolCTT" Content="Chris Titus Tech - WinUtil" Height="36" Margin="0,0,0,8" HorizontalAlignment="Left" Width="320" FontSize="13"/>
                    <Button Name="BtnToolWinScript" Content="WinScript - Otimizacao Completa" Height="36" Margin="0,0,0,8" HorizontalAlignment="Left" Width="320" FontSize="13"/>
                    <Button Name="BtnToolWinhance" Content="Winhance - Windows Enhancement Utility" Height="36" Margin="0,0,0,8" HorizontalAlignment="Left" Width="320" FontSize="13"/>
                    <Button Name="BtnToolDebloat" Content="Windows Debloater (Script Classico)" Height="36" Margin="0,0,0,8" HorizontalAlignment="Left" Width="320" FontSize="13"/>
                    <Button Name="BtnToolRaphire" Content="Win11Debloat (Raphire) - Atencao, Cuidado" Height="36" Margin="0,0,0,8" HorizontalAlignment="Left" Width="320" FontSize="13" Background="#7A4A0E" Foreground="White"/>
                </StackPanel>
            </TabItem>
        </TabControl>

        <WrapPanel Grid.Row="2" Margin="0,10,0,0">
            <Button Name="BtnInstalar" Content="Instalar Selecionados" Width="180" Height="34" Margin="0,0,8,8" Background="#0E7A0D" Foreground="White" FontWeight="Bold"/>
            <Button Name="BtnRetryFailed" Content="Tentar Novamente (Erros)" Width="180" Height="34" Margin="0,0,8,8" IsEnabled="False"/>
            <Button Name="BtnRestore" Content="Criar Ponto de Restauracao" Width="200" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnUpdateAll" Content="Verificar Atualizacoes" Width="180" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnCleanup" Content="Limpar Cache/Temp" Width="160" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnOpenLog" Content="Abrir Log" Width="120" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnSaveProfile" Content="Salvar Selecao" Width="140" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnLoadProfile" Content="Carregar Selecao" Width="140" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnExportApps" Content="Exportar Backup de Apps" Width="190" Height="34" Margin="0,0,8,8"/>
        </WrapPanel>

        <ProgressBar Grid.Row="3" Name="ProgressBarInstall" Height="20" Minimum="0" Maximum="1" Value="0" Margin="0,0,0,8"/>

        <TextBox Grid.Row="4" Name="TxtLog" Background="#0C0C0C" Foreground="#D4D4D4" FontFamily="Consolas" FontSize="12"
                  IsReadOnly="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>

        <WrapPanel Grid.Row="5" Margin="0,10,0,0" HorizontalAlignment="Right">
            <TextBlock Name="TxtStatus" Foreground="White" VerticalAlignment="Center" Margin="0,0,20,0" Text="Pronto."/>
            <Button Name="BtnReiniciar" Content="Reiniciar PC" Width="120" Height="30" Margin="0,0,8,0"/>
            <Button Name="BtnDesligar" Content="Desligar PC" Width="120" Height="30" Margin="0,0,8,0"/>
            <Button Name="BtnSair" Content="Sair" Width="90" Height="30"/>
        </WrapPanel>
    </Grid>
</Window>
'@

$Reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($Reader)

# ---------------------------------------------------
# REFERENCIAS AOS CONTROLES
# ---------------------------------------------------
$PanelRuntimes        = $Window.FindName('PanelRuntimes')
$PanelPrincipal       = $Window.FindName('PanelPrincipal')
$PanelOpcionais       = $Window.FindName('PanelOpcionais')
$ImgOsLogo            = $Window.FindName('ImgOsLogo')
$TxtOsInfo            = $Window.FindName('TxtOsInfo')
$TxtTitle             = $Window.FindName('TxtTitle')
$TxtTitle.Text        = "Instalador Multi-Modos Winget PRO $ScriptVersion"
$BtnSelAllRuntimes    = $Window.FindName('BtnSelAllRuntimes')
$BtnClearRuntimes     = $Window.FindName('BtnClearRuntimes')
$BtnSelAllPrincipal   = $Window.FindName('BtnSelAllPrincipal')
$BtnClearPrincipal    = $Window.FindName('BtnClearPrincipal')
$BtnSelAllOpcionais   = $Window.FindName('BtnSelAllOpcionais')
$BtnClearOpcionais    = $Window.FindName('BtnClearOpcionais')
$BtnToolMAS           = $Window.FindName('BtnToolMAS')
$BtnToolCTT           = $Window.FindName('BtnToolCTT')
$BtnToolWinScript     = $Window.FindName('BtnToolWinScript')
$BtnToolWinhance      = $Window.FindName('BtnToolWinhance')
$BtnToolDebloat       = $Window.FindName('BtnToolDebloat')
$BtnToolRaphire       = $Window.FindName('BtnToolRaphire')
$BtnInstalar          = $Window.FindName('BtnInstalar')
$BtnRetryFailed       = $Window.FindName('BtnRetryFailed')
$BtnRestore           = $Window.FindName('BtnRestore')
$BtnUpdateAll         = $Window.FindName('BtnUpdateAll')
$BtnCleanup           = $Window.FindName('BtnCleanup')
$BtnOpenLog           = $Window.FindName('BtnOpenLog')
$BtnSaveProfile       = $Window.FindName('BtnSaveProfile')
$BtnLoadProfile       = $Window.FindName('BtnLoadProfile')
$BtnExportApps        = $Window.FindName('BtnExportApps')
$ProgressBarInstall   = $Window.FindName('ProgressBarInstall')
$TxtLog               = $Window.FindName('TxtLog')
$TxtStatus            = $Window.FindName('TxtStatus')
$BtnReiniciar         = $Window.FindName('BtnReiniciar')
$BtnDesligar          = $Window.FindName('BtnDesligar')
$BtnSair              = $Window.FindName('BtnSair')

# ---------------------------------------------------
# DETECCAO DA VERSAO DO WINDOWS + LOGO (baixado do GitHub)
# ---------------------------------------------------
# O logo (win10.png ou win11.png) e baixado de $LogoBaseUrl toda vez que
# o script abre, de forma assincrona (nao trava a janela). Se o download
# falhar por qualquer motivo, o espaco do logo fica so oculto.
$ImgOsLogo.Visibility = 'Collapsed'

try {
    $OsInfo    = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $BuildNum  = [int]$OsInfo.BuildNumber
    $OsCaption = $OsInfo.Caption -replace 'Microsoft ', ''
    $Arch      = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $LogoFileName = if ($BuildNum -ge 22000) { 'Win11.png' } else { 'Win10.png' }
    $TxtOsInfo.Text = "$OsCaption ($Arch) - Build $BuildNum"
} catch {
    $LogoFileName = $null
    $TxtOsInfo.Text = 'Nao foi possivel detectar a versao do Windows.'
}

if ($LogoFileName) {
    $LogoUrl = $LogoBaseUrl + $LogoFileName
    $script:LogoJob = Start-Job -ScriptBlock {
        param($Url)
        try {
            $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
            return [PSCustomObject]@{ Bytes = $Response.Content; Error = $null }
        } catch {
            return [PSCustomObject]@{ Bytes = $null; Error = $_.Exception.Message }
        }
    } -ArgumentList $LogoUrl

    $TimerLogo = New-Object System.Windows.Threading.DispatcherTimer
    $TimerLogo.Interval = [TimeSpan]::FromMilliseconds(400)
    $TimerLogo.Add_Tick({
        if ($null -eq $script:LogoJob) { return }
        if ($script:LogoJob.State -ne 'Completed') { return }

        $Result = Receive-Job -Job $script:LogoJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:LogoJob -Force
        $script:LogoJob = $null
        $TimerLogo.Stop()

        $Bytes = $Result.Bytes
        if ($Bytes -and $Bytes.Length -gt 0) {
            try {
                $Stream = New-Object System.IO.MemoryStream(, [byte[]]$Bytes)
                $Bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $Bitmap.BeginInit()
                $Bitmap.CacheOption = 'OnLoad'
                $Bitmap.StreamSource = $Stream
                $Bitmap.EndInit()
                $Bitmap.Freeze()
                $ImgOsLogo.Source = $Bitmap
                $ImgOsLogo.Visibility = 'Visible'
            } catch {
                $ImgOsLogo.Visibility = 'Collapsed'
                $TxtStatus.Text = "Logo baixado mas nao pode ser exibido: $($_.Exception.Message)"
            }
        } else {
            $ImgOsLogo.Visibility = 'Collapsed'
            $TxtStatus.Text = "Nao foi possivel baixar o logo ($LogoUrl): $($Result.Error)"
        }
    })
    $TimerLogo.Start()
}


# ---------------------------------------------------
# POPULAR CHECKBOXES
# ---------------------------------------------------
function New-AppCheckBox {
    param($AppItem)
    $Cb = New-Object System.Windows.Controls.CheckBox
    $Cb.Content    = $AppItem.Name
    $Cb.Tag        = $AppItem
    $Cb.Foreground = 'White'
    $Cb.Margin     = '4'
    $Cb.FontSize   = 13
    return $Cb
}

foreach ($Item in $Runtimes)  { $PanelRuntimes.Children.Add((New-AppCheckBox $Item))  | Out-Null }
foreach ($Item in $Principal) { $PanelPrincipal.Children.Add((New-AppCheckBox $Item)) | Out-Null }
foreach ($Item in $Opcionais) { $PanelOpcionais.Children.Add((New-AppCheckBox $Item)) | Out-Null }

# ---------------------------------------------------
# VERIFICACAO DE PROGRAMAS JA INSTALADOS (JOB + TIMER)
# ---------------------------------------------------
$script:InstalledCheckJob = Start-Job -ScriptBlock {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    & winget list --accept-source-agreements 2>&1 | Out-String
}

$TimerInstalledCheck = New-Object System.Windows.Threading.DispatcherTimer
$TimerInstalledCheck.Interval = [TimeSpan]::FromMilliseconds(600)
$TimerInstalledCheck.Add_Tick({
    if ($null -eq $script:InstalledCheckJob) { return }
    if ($script:InstalledCheckJob.State -ne 'Completed') { return }

    $Output = Receive-Job -Job $script:InstalledCheckJob -ErrorAction SilentlyContinue
    Remove-Job -Job $script:InstalledCheckJob -Force
    $script:InstalledCheckJob = $null
    $TimerInstalledCheck.Stop()

    foreach ($Panel in @($PanelRuntimes, $PanelPrincipal, $PanelOpcionais)) {
        foreach ($Cb in $Panel.Children) {
            $AppItem = $Cb.Tag
            if ($Output -match [Regex]::Escape($AppItem.Id)) {
                $Cb.Content    = $AppItem.Name + '  (ja instalado)'
                $Cb.Foreground = '#4EC9B0'
            }
        }
    }
    $TxtStatus.Text = 'Verificacao de programas instalados concluida.'
})
$TxtStatus.Text = 'Verificando programas ja instalados...'
$TimerInstalledCheck.Start()

# ---------------------------------------------------
# BOTOES SELECIONAR TODOS / LIMPAR SELECAO
# ---------------------------------------------------
$BtnSelAllRuntimes.Add_Click({ foreach ($Cb in $PanelRuntimes.Children)  { $Cb.IsChecked = $true } })
$BtnClearRuntimes.Add_Click({  foreach ($Cb in $PanelRuntimes.Children)  { $Cb.IsChecked = $false } })
$BtnSelAllPrincipal.Add_Click({ foreach ($Cb in $PanelPrincipal.Children) { $Cb.IsChecked = $true } })
$BtnClearPrincipal.Add_Click({  foreach ($Cb in $PanelPrincipal.Children) { $Cb.IsChecked = $false } })
$BtnSelAllOpcionais.Add_Click({ foreach ($Cb in $PanelOpcionais.Children) { $Cb.IsChecked = $true } })
$BtnClearOpcionais.Add_Click({  foreach ($Cb in $PanelOpcionais.Children) { $Cb.IsChecked = $false } })

# ---------------------------------------------------
# FERRAMENTAS EXTRAS (abrem em uma janela de PowerShell separada)
# ---------------------------------------------------
function Start-ExternalTool {
    param([string]$Url)
    Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$Url' | iex`""
}

$BtnToolMAS.Add_Click({ Start-ExternalTool -Url 'https://get.activated.win' })
$BtnToolCTT.Add_Click({ Start-ExternalTool -Url 'https://christitus.com/win' })
$BtnToolWinScript.Add_Click({ Start-ExternalTool -Url 'https://winscript.cc/irm' })
$BtnToolWinhance.Add_Click({ Start-ExternalTool -Url 'https://get.winhance.net' })
$BtnToolDebloat.Add_Click({ Start-ExternalTool -Url 'https://git.io/debloat' })
$BtnToolRaphire.Add_Click({
    $Resp = [System.Windows.MessageBox]::Show('O Win11Debloat remove aplicativos e recursos do Windows de forma bastante agressiva. Tem certeza que deseja continuar?', 'Atencao', 'YesNo', 'Warning')
    if ($Resp -eq 'Yes') { Start-ExternalTool -Url 'https://debloat.raphi.re/' }
})

# ---------------------------------------------------
# INSTALACAO DOS SELECIONADOS (JOB + TIMER)
# ---------------------------------------------------
$script:InstallJob      = $null
$script:TotalOK         = 0
$script:TotalAtualizado = 0
$script:TotalErro       = 0
$script:FailedItems     = @()

$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(400)

function Start-InstallJob {
    param($ItemsToInstall)

    if (-not $ItemsToInstall -or $ItemsToInstall.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Nao ha itens para instalar.', 'Aviso', 'OK', 'Warning') | Out-Null
        return
    }

    $BtnInstalar.IsEnabled = $false
    $BtnRetryFailed.IsEnabled = $false
    $ProgressBarInstall.Maximum = $ItemsToInstall.Count
    $ProgressBarInstall.Value = 0
    $TxtLog.Clear()
    $script:TotalOK = 0
    $script:TotalAtualizado = 0
    $script:TotalErro = 0
    $script:FailedItems = @()
    $TxtStatus.Text = 'Instalando...'

    $script:InstallJob = Start-Job -ScriptBlock {
        param($Items, $Log)
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8

        # Alguns instaladores (Spotify sempre, outros as vezes por causa de hash
        # desatualizado no manifesto) se recusam a rodar em processo elevado.
        # Este contorno dispara a instalacao via explorer.exe, que roda no nivel
        # normal do usuario (nao-elevado), e aguarda a conclusao por um marcador.
        function Install-PackageNonElevated {
            param([string]$PackageId, [string]$LogPath)
            try {
                $WingetExe = (Get-Command winget -ErrorAction Stop).Source
                $Marker    = Join-Path $env:TEMP ('nonelev_marker_' + [guid]::NewGuid().ToString('N') + '.txt')
                $OutLog    = Join-Path $env:TEMP ('nonelev_out_' + [guid]::NewGuid().ToString('N') + '.txt')
                $HelperBat = Join-Path $env:TEMP ('nonelev_install_' + [guid]::NewGuid().ToString('N') + '.bat')
                $SourceArg = if ($PackageId -eq '9NKSQGP7F2NH') { 'msstore' } else { 'winget' }
                $BatBody   = "@echo off`r`nchcp 65001 >nul`r`n`"$WingetExe`" install --id $PackageId --source $SourceArg --silent --accept-source-agreements --accept-package-agreements --ignore-security-hash > `"$OutLog`" 2>&1`r`necho %errorlevel% > `"$Marker`"`r`n"
                Set-Content -Path $HelperBat -Value $BatBody -Encoding ASCII

                Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$HelperBat`""

                $Waited = 0
                while (-not (Test-Path $Marker) -and $Waited -lt 180) {
                    Start-Sleep -Seconds 2
                    $Waited += 2
                }

                if (Test-Path $Marker) {
                    $ResultCode = [int]((Get-Content -Path $Marker -Raw).Trim())
                    Remove-Item -Path $Marker -Force -ErrorAction SilentlyContinue
                } else {
                    $ResultCode = -1
                    Add-Content -Path $LogPath -Value '[AVISO] Tempo limite atingido aguardando a instalacao nao-elevada.' -Encoding utf8
                }

                if (Test-Path $OutLog) {
                    Get-Content -Path $OutLog -Raw -Encoding UTF8 | Add-Content -Path $LogPath -Encoding utf8
                    Remove-Item -Path $OutLog -Force -ErrorAction SilentlyContinue
                }
                Remove-Item -Path $HelperBat -Force -ErrorAction SilentlyContinue

                return $ResultCode
            } catch {
                Add-Content -Path $LogPath -Value ('[ERRO] Falha ao preparar instalacao nao-elevada: ' + $_.Exception.Message) -Encoding utf8
                return -1
            }
        }

        foreach ($It in $Items) {
            Add-Content -Path $Log -Value ('[PROCESSO] Tentando instalar/verificar ' + $It.Name) -Encoding utf8
            Add-Content -Path $Log -Value ('----- SAIDA WINGET: ' + $It.Name + ' -----') -Encoding utf8

            if ($It.Id -eq 'Spotify.Spotify') {
                # Spotify sempre recusa contexto elevado - vai direto pelo caminho nao-elevado
                Add-Content -Path $Log -Value '[INFO] Spotify nao permite instalacao em contexto elevado - usando processo nao-elevado (pode levar ate 3 minutos)' -Encoding utf8
                $Code = Install-PackageNonElevated -PackageId $It.Id -LogPath $Log
            } else {
                # Especifica a fonte explicitamente para nao depender de consultar a
                # fonte "msstore" quando nao e necessario (evita travar se a msstore
                # estiver com problema de certificado, comum em Windows recem-instalado).
                $Source  = if ($It.Id -eq '9NKSQGP7F2NH') { 'msstore' } else { 'winget' }
                $Out     = & winget install --id $It.Id --source $Source --silent --accept-source-agreements --accept-package-agreements --ignore-security-hash 2>&1
                $Code    = $LASTEXITCODE
                $OutText = ($Out | Out-String)
                $Out | Add-Content -Path $Log -Encoding utf8

                if ($Code -ne 0 -and $Code -ne -1978335189 -and $OutText -match '(?i)hash' -and $OutText -match '(?i)admin') {
                    Add-Content -Path $Log -Value '[INFO] Falha por restricao de hash em contexto elevado - tentando via processo nao-elevado...' -Encoding utf8
                    $Code = Install-PackageNonElevated -PackageId $It.Id -LogPath $Log
                }
            }

            Add-Content -Path $Log -Value '' -Encoding utf8
            Add-Content -Path $Log -Value '---------------------------------------------------' -Encoding utf8
            [PSCustomObject]@{ Name = $It.Name; Id = $It.Id; ExitCode = $Code }
        }
    } -ArgumentList $ItemsToInstall, $LogFile

    $Timer.Start()
}

$BtnInstalar.Add_Click({
    $Selected = New-Object System.Collections.Generic.List[Object]
    foreach ($Panel in @($PanelRuntimes, $PanelPrincipal, $PanelOpcionais)) {
        foreach ($Cb in $Panel.Children) {
            if ($Cb.IsChecked -eq $true) { $Selected.Add($Cb.Tag) }
        }
    }

    if ($Selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Selecione ao menos um item antes de instalar.', 'Aviso', 'OK', 'Warning') | Out-Null
        return
    }

    $RestoreResp = [System.Windows.MessageBox]::Show('Deseja criar um Ponto de Restauracao do Windows antes de instalar?', 'Ponto de Restauracao', 'YesNo', 'Question')
    if ($RestoreResp -eq 'Yes') {
        Invoke-CreateRestorePoint
    }

    # Expande IrfanView -> Plugins automaticamente
    # (o pacote de Idioma BR nao existe no winget, apenas no Chocolatey)
    $Expanded = New-Object System.Collections.Generic.List[Object]
    foreach ($It in $Selected) {
        $Expanded.Add($It)
        if ($It.Id -eq 'IrfanSkiljan.IrfanView') {
            $Expanded.Add([PSCustomObject]@{ Name = 'IrfanView - Plugins'; Id = 'IrfanSkiljan.IrfanView.PlugIns' })
        }
    }

    Start-InstallJob -ItemsToInstall $Expanded.ToArray()
})

$BtnRetryFailed.Add_Click({
    Start-InstallJob -ItemsToInstall $script:FailedItems
})

$Timer.Add_Tick({
    if ($null -eq $script:InstallJob) { return }
    $Results = Receive-Job -Job $script:InstallJob -ErrorAction SilentlyContinue
    foreach ($R in $Results) {
        $ProgressBarInstall.Value++
        if ($R.ExitCode -eq 0) {
            $script:TotalOK++
            $TxtLog.AppendText("[OK] " + $R.Name + "`r`n")
        } elseif ($R.ExitCode -eq -1978335189) {
            $script:TotalAtualizado++
            $TxtLog.AppendText("[ATUALIZADO] " + $R.Name + " (ja estava atualizado)`r`n")
        } else {
            $script:TotalErro++
            $script:FailedItems += [PSCustomObject]@{ Name = $R.Name; Id = $R.Id }
            $TxtLog.AppendText("[ERRO] " + $R.Name + " - Codigo: " + $R.ExitCode + "`r`n")
        }
        $TxtLog.ScrollToEnd()
    }
    if ($script:InstallJob.State -eq 'Completed') {
        $Timer.Stop()
        Remove-Job -Job $script:InstallJob -Force
        $script:InstallJob = $null
        $BtnInstalar.IsEnabled = $true
        $BtnRetryFailed.IsEnabled = ($script:FailedItems.Count -gt 0)
        $TxtStatus.Text = "Concluido: OK=$($script:TotalOK)  Atualizados=$($script:TotalAtualizado)  Erros=$($script:TotalErro)"
        Add-Content -Path $LogFile -Value '' -Encoding utf8
        Add-Content -Path $LogFile -Value '===================================================' -Encoding utf8
        Add-Content -Path $LogFile -Value 'RESUMO DESTA EXECUCAO' -Encoding utf8
        Add-Content -Path $LogFile -Value ('Instalados/Atualizados com sucesso  : ' + $script:TotalOK) -Encoding utf8
        Add-Content -Path $LogFile -Value ('Ja atualizados (sem acao necessaria): ' + $script:TotalAtualizado) -Encoding utf8
        Add-Content -Path $LogFile -Value ('Falharam                            : ' + $script:TotalErro) -Encoding utf8
        Add-Content -Path $LogFile -Value '===================================================' -Encoding utf8
        [System.Windows.MessageBox]::Show("Instalacao concluida!`n`nOK: $($script:TotalOK)`nAtualizados: $($script:TotalAtualizado)`nErros: $($script:TotalErro)", 'Finalizado', 'OK', 'Information') | Out-Null
    }
})

# ---------------------------------------------------
# VERIFICAR / ATUALIZAR TODOS OS PROGRAMAS (JOB + TIMER)
# ---------------------------------------------------
$script:UpgradeJob   = $null
$script:UpgradeStage = $null

$TimerUpgrade = New-Object System.Windows.Threading.DispatcherTimer
$TimerUpgrade.Interval = [TimeSpan]::FromMilliseconds(500)

$BtnUpdateAll.Add_Click({
    $BtnUpdateAll.IsEnabled = $false
    $TxtStatus.Text = 'Consultando atualizacoes disponiveis...'
    $script:UpgradeStage = 'listing'
    $script:UpgradeJob = Start-Job -ScriptBlock {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        & winget upgrade --accept-source-agreements 2>&1 | Out-String
    }
    $TimerUpgrade.Start()
})

$TimerUpgrade.Add_Tick({
    if ($null -eq $script:UpgradeJob) { return }
    if ($script:UpgradeJob.State -ne 'Completed') { return }

    $Output = Receive-Job -Job $script:UpgradeJob -ErrorAction SilentlyContinue
    Remove-Job -Job $script:UpgradeJob -Force
    $script:UpgradeJob = $null
    $TimerUpgrade.Stop()

    if ($script:UpgradeStage -eq 'listing') {
        Add-Content -Path $LogFile -Value '----- SAIDA WINGET: Lista de atualizacoes disponiveis -----' -Encoding utf8
        Add-Content -Path $LogFile -Value $Output -Encoding utf8
        $TxtLog.AppendText("`r`n--- Atualizacoes disponiveis ---`r`n")
        $TxtLog.AppendText(($Output | Out-String))
        $TxtLog.ScrollToEnd()

        $Resp = [System.Windows.MessageBox]::Show("Veja a lista de atualizacoes no log acima.`n`nDeseja atualizar TODOS os programas listados?", 'Atualizar Tudo', 'YesNo', 'Question')
        if ($Resp -eq 'Yes') {
            $script:UpgradeStage = 'upgrading'
            $TxtStatus.Text = 'Atualizando todos os programas...'
            $script:UpgradeJob = Start-Job -ScriptBlock {
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                $OutputEncoding = [System.Text.Encoding]::UTF8
                & winget upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
            }
            $TimerUpgrade.Start()
        } else {
            $BtnUpdateAll.IsEnabled = $true
            $TxtStatus.Text = 'Atualizacao cancelada pelo usuario.'
            Add-Content -Path $LogFile -Value '[PULADO] Usuario optou por nao atualizar apos ver a lista.' -Encoding utf8
        }
    } elseif ($script:UpgradeStage -eq 'upgrading') {
        Add-Content -Path $LogFile -Value '----- SAIDA WINGET: Atualizacao geral (winget upgrade --all) -----' -Encoding utf8
        Add-Content -Path $LogFile -Value $Output -Encoding utf8
        $TxtLog.AppendText("`r`n--- Atualizacao geral concluida ---`r`n")
        $TxtLog.ScrollToEnd()
        $BtnUpdateAll.IsEnabled = $true
        $TxtStatus.Text = 'Atualizacao geral concluida.'
        [System.Windows.MessageBox]::Show('Atualizacao geral concluida! Veja o log para detalhes.', 'Finalizado', 'OK', 'Information') | Out-Null
    }
})

# ---------------------------------------------------
# PONTO DE RESTAURACAO DO WINDOWS
# ---------------------------------------------------
function Invoke-CreateRestorePoint {
    $TxtStatus.Text = 'Criando ponto de restauracao...'
    $TxtLog.AppendText("[PROCESSO] Tentando criar Ponto de Restauracao do Windows`r`n")
    Add-Content -Path $LogFile -Value '[PROCESSO] Tentando criar Ponto de Restauracao do Windows' -Encoding utf8
    try {
        Checkpoint-Computer -Description 'InstaladorWingetPRO GUI - Antes da instalacao' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        $TxtLog.AppendText("[OK] Ponto de restauracao criado com sucesso.`r`n")
        Add-Content -Path $LogFile -Value '[SUCESSO] Ponto de restauracao criado com sucesso.' -Encoding utf8
        $TxtStatus.Text = 'Ponto de restauracao criado.'
    } catch {
        $ErrMsg = $_.Exception.Message
        $TxtLog.AppendText("[AVISO] Nao foi possivel criar o ponto de restauracao: " + $ErrMsg + "`r`n")
        Add-Content -Path $LogFile -Value ('[AVISO] Falha ao criar ponto de restauracao: ' + $ErrMsg) -Encoding utf8
        $TxtStatus.Text = 'Falha ao criar ponto de restauracao (veja o log).'
    }
    $TxtLog.ScrollToEnd()
}

$BtnRestore.Add_Click({
    $BtnRestore.IsEnabled = $false
    Invoke-CreateRestorePoint
    $BtnRestore.IsEnabled = $true
})

# ---------------------------------------------------
# LIMPEZA DE CACHE / ARQUIVOS TEMPORARIOS
# ---------------------------------------------------
$BtnCleanup.Add_Click({
    $BtnCleanup.IsEnabled = $false
    $TxtStatus.Text = 'Limpando cache e arquivos temporarios...'
    $TxtLog.AppendText("[LIMPEZA] Iniciando rotina de limpeza do sistema`r`n")
    Add-Content -Path $LogFile -Value '[LIMPEZA] Iniciando rotina de limpeza do sistema' -Encoding utf8
    try { & winget cache clean 2>&1 | Out-Null } catch {}
    try { Remove-Item -Path (Join-Path $env:TEMP '*') -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -Path 'C:\Windows\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -Path 'C:\Windows\Prefetch\*' -Force -ErrorAction SilentlyContinue } catch {}
    $TxtLog.AppendText("[OK] Limpeza concluida.`r`n")
    Add-Content -Path $LogFile -Value '[SUCESSO] Limpeza concluida.' -Encoding utf8
    $TxtStatus.Text = 'Limpeza concluida.'
    $TxtLog.ScrollToEnd()
    $BtnCleanup.IsEnabled = $true
})

# ---------------------------------------------------
# ABRIR LOG
# ---------------------------------------------------
$BtnOpenLog.Add_Click({
    if (Test-Path $LogFile) {
        Start-Process notepad.exe $LogFile
    } else {
        [System.Windows.MessageBox]::Show('O arquivo de log ainda nao foi criado.', 'Aviso', 'OK', 'Warning') | Out-Null
    }
})

# ---------------------------------------------------
# SALVAR / CARREGAR PERFIL DE SELECAO
# ---------------------------------------------------
$ProfilePath = Join-Path $env:APPDATA 'InstaladorWingetPRO\perfil_selecao.json'

$BtnSaveProfile.Add_Click({
    $SelectedIds = @()
    foreach ($Panel in @($PanelRuntimes, $PanelPrincipal, $PanelOpcionais)) {
        foreach ($Cb in $Panel.Children) {
            if ($Cb.IsChecked -eq $true) { $SelectedIds += $Cb.Tag.Id }
        }
    }
    if ($SelectedIds.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Nenhum item selecionado para salvar.', 'Aviso', 'OK', 'Warning') | Out-Null
        return
    }
    $Dir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $SelectedIds | ConvertTo-Json | Set-Content -Path $ProfilePath -Encoding utf8
    [System.Windows.MessageBox]::Show("Perfil salvo com $($SelectedIds.Count) item(ns).", 'Perfil Salvo', 'OK', 'Information') | Out-Null
})

$BtnLoadProfile.Add_Click({
    if (-not (Test-Path $ProfilePath)) {
        [System.Windows.MessageBox]::Show('Nenhum perfil salvo foi encontrado.', 'Aviso', 'OK', 'Warning') | Out-Null
        return
    }
    try {
        $Ids = @(Get-Content -Path $ProfilePath -Raw | ConvertFrom-Json)
    } catch {
        [System.Windows.MessageBox]::Show('O arquivo de perfil esta corrompido ou invalido.', 'Erro', 'OK', 'Error') | Out-Null
        return
    }
    $Matched = 0
    foreach ($Panel in @($PanelRuntimes, $PanelPrincipal, $PanelOpcionais)) {
        foreach ($Cb in $Panel.Children) {
            if ($Ids -contains $Cb.Tag.Id) {
                $Cb.IsChecked = $true
                $Matched++
            } else {
                $Cb.IsChecked = $false
            }
        }
    }
    [System.Windows.MessageBox]::Show("Perfil carregado com $Matched item(ns) marcado(s).", 'Perfil Carregado', 'OK', 'Information') | Out-Null
})

# ---------------------------------------------------
# EXPORTAR BACKUP DE APPS INSTALADOS (JOB + TIMER)
# ---------------------------------------------------
$script:ExportJob  = $null
$script:ExportPath = $null

$TimerExport = New-Object System.Windows.Threading.DispatcherTimer
$TimerExport.Interval = [TimeSpan]::FromMilliseconds(500)

$BtnExportApps.Add_Click({
    $BtnExportApps.IsEnabled = $false
    $TxtStatus.Text = 'Exportando lista de apps instalados...'
    $script:ExportPath = Join-Path $env:USERPROFILE ("Desktop\Backup_Apps_Instalados_" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + ".json")
    $script:ExportJob = Start-Job -ScriptBlock {
        param($Path)
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        & winget export -o $Path --accept-source-agreements 2>&1 | Out-String
    } -ArgumentList $script:ExportPath
    $TimerExport.Start()
})

$TimerExport.Add_Tick({
    if ($null -eq $script:ExportJob) { return }
    if ($script:ExportJob.State -ne 'Completed') { return }

    $Output = Receive-Job -Job $script:ExportJob -ErrorAction SilentlyContinue
    Remove-Job -Job $script:ExportJob -Force
    $script:ExportJob = $null
    $TimerExport.Stop()
    $BtnExportApps.IsEnabled = $true

    if (Test-Path $script:ExportPath) {
        $TxtStatus.Text = 'Backup de apps exportado com sucesso.'
        Add-Content -Path $LogFile -Value ('[SUCESSO] Backup de apps instalados exportado para: ' + $script:ExportPath) -Encoding utf8
        [System.Windows.MessageBox]::Show("Backup salvo em:`n$($script:ExportPath)", 'Exportacao Concluida', 'OK', 'Information') | Out-Null
    } else {
        $TxtStatus.Text = 'Falha ao exportar backup de apps.'
        Add-Content -Path $LogFile -Value ('[ERRO] Falha ao exportar backup de apps: ' + $Output) -Encoding utf8
        [System.Windows.MessageBox]::Show('Falha ao exportar o backup. Veja o log para detalhes.', 'Erro', 'OK', 'Error') | Out-Null
    }
})

# ---------------------------------------------------
# ACOES FINAIS DO SISTEMA
# ---------------------------------------------------
$BtnReiniciar.Add_Click({
    $Resp = [System.Windows.MessageBox]::Show('Deseja reiniciar o computador agora?', 'Reiniciar', 'YesNo', 'Question')
    if ($Resp -eq 'Yes') {
        Start-Process shutdown.exe -ArgumentList '/r','/t','10','/c','Script concluido. Reiniciando o sistema.'
    }
})

$BtnDesligar.Add_Click({
    $Resp = [System.Windows.MessageBox]::Show('Deseja desligar o computador agora?', 'Desligar', 'YesNo', 'Question')
    if ($Resp -eq 'Yes') {
        Start-Process shutdown.exe -ArgumentList '/s','/t','10','/c','Script concluido. Desligando o sistema.'
    }
})

$BtnSair.Add_Click({ $Window.Close() })

$Window.Add_Closing({
    if ($Timer.IsEnabled) { $Timer.Stop() }
    if ($TimerUpgrade.IsEnabled) { $TimerUpgrade.Stop() }
    if ($TimerInstalledCheck.IsEnabled) { $TimerInstalledCheck.Stop() }
    if ($TimerExport.IsEnabled) { $TimerExport.Stop() }
    if ($TimerLogo -and $TimerLogo.IsEnabled) { $TimerLogo.Stop() }
    if ($script:InstallJob) { Remove-Job -Job $script:InstallJob -Force -ErrorAction SilentlyContinue }
    if ($script:UpgradeJob) { Remove-Job -Job $script:UpgradeJob -Force -ErrorAction SilentlyContinue }
    if ($script:InstalledCheckJob) { Remove-Job -Job $script:InstalledCheckJob -Force -ErrorAction SilentlyContinue }
    if ($script:ExportJob) { Remove-Job -Job $script:ExportJob -Force -ErrorAction SilentlyContinue }
    if ($script:LogoJob) { Remove-Job -Job $script:LogoJob -Force -ErrorAction SilentlyContinue }
})

# ---------------------------------------------------
# EXIBIR JANELA
# ---------------------------------------------------
$Window.ShowDialog() | Out-Null
