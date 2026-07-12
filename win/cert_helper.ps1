Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security

$HELPERVERSION="0.2"

function save_cert ([System.Security.Cryptography.X509Certificates.X509Certificate2]$cert, [String]$file) {
  $oPem=new-object System.Text.StringBuilder
  $oPem.AppendLine("-----BEGIN CERTIFICATE-----")
  $oPem.AppendLine([System.Convert]::ToBase64String($cert.RawData,1))
  $oPem.AppendLine("-----END CERTIFICATE-----")
  $oPem.ToString() | out-file -filepath $file -force -ErrorAction Stop
}


function ask_password {
  $script:password=""

  $read_password = {
    $script:password=$textBoxPassword.Text
    $formPassword.close()
  }

  $formPassword = [Windows.Forms.Form] @{ 
    Text = 'Password'
    Size = [Drawing.Size]::new(240, 120)
    StartPosition = 'CenterScreen'
    AutoScaleMode   = 'Font'
    FormBorderStyle = "FixedToolWindow"
  }
  $textBoxPassword = [Windows.Forms.TextBox] @{
    Text     = ''
    PasswordChar = '*'
    Location = [Drawing.Point]::new(10, 10)
    Width = 205
    Font     = [Drawing.Font]::new($form.Font.Name, 12)
  }
  $buttonPasswordOk = [Windows.Forms.Button] @{
    Text     = 'Ok'
    Location = [Drawing.Point]::new(90, 45)
    Width = 50
    Height = 30
    Font     = [Drawing.Font]::new($form.Font.Name, 14)
  }
  $formPassword.Controls.AddRange(@(
    $textBoxPassword
    $buttonPasswordOk
  ))
  $buttonPasswordOk.Add_click($read_password)
  $textBoxPassword.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
      Invoke-Command -ScriptBlock $read_password
    }
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
      $formPassword.close()
    }
  })
  $buttonPasswordOk.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
      $formPassword.close()
    }
  })

  $formPassword.showdialog() | Out-Null
  return $password
}


#####################################################
$buttonExportClick = {
  $certcollection = [System.Security.Cryptography.X509Certificates.X509Certificate2[]](dir Cert:\CurrentUser\My)
  if($certcollection -eq $null) {
    [System.Windows.Forms.MessageBox]::Show("Nothing to export", 'Warning', 0, 48)
    return
  }
  $selected = [System.Security.Cryptography.X509Certificates.X509Certificate2UI]::SelectfromCollection($certcollection,'Choose a certificate','Choose a certificate',0)
  if ( ($selected -eq $null) -or ($selected.count -ne 1) ) {
    return
  }

  $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('MyComputer')
    Filter = "p12 files (*.p12)|*.p12|pfx files (*.pfx)|*.pfx|All files (*.*)|*.*"
  }
  $FileBrowser.ShowDialog()

  $container_file = $FileBrowser.Filename
  if ( $container_file.length -lt 1 ) {
    return
  }

  $ContainerPasswd = ConvertTo-SecureString -String (ask_password) -Force -AsPlainText

  $params = @{
    Cert = $selected[0]
    FilePath = "$container_file"
    ChainOption = 'BuildChain'
    Force = $true
    NoProperties = $true
    Password = $ContainerPasswd
  }

  try {
    Export-PfxCertificate @params
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to export selected chain", 'Error', 0, 48)
    return
  }

  [System.Windows.Forms.MessageBox]::Show("Export done.", 'Success!', 0, 64)
}


#####################################################
$buttonImportClick = {
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('MyComputer')
    Filter = "p12 files (*.p12)|*.p12|pfx files (*.pfx)|*.pfx|All files (*.*)|*.*"
  }
  $FileBrowser.ShowDialog()

  $container_file = $FileBrowser.Filename
  if ( $container_file.length -lt 1 -or !(Test-Path -Path $container_file -PathType leaf) ) {
    return
  }

  $ContainerPasswd = ask_password

  $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
  try {
    $certCollection.Import("$container_file","$ContainerPasswd", 1 -bor 4 -bor 16)
    if ( $certCollection.count -ne 2 ) {
      [System.Windows.Forms.MessageBox]::Show("Only 2 certs expected", 'Error', 0, 48)
      return
    }
    foreach ($x509 in $certCollection) {
      if ( $x509.issuer -eq $x509.subject ) {

        save_cert $x509 "$PSScriptRoot\ca.crt"
        if ( !(Test-Path -Path "$PSScriptRoot\ca.crt" -PathType leaf) ) {
          [System.Windows.Forms.MessageBox]::Show("Cannot save CA cert", 'Error', 0, 48)
          return
        }
        $process = start-process -FilePath "certutil.exe" -ArgumentList "-f -enterprise -addstore `"Root`" `"$PSScriptRoot\ca.crt`"" -verb runas -wait -PassThru -WindowStyle Hidden
        if($process.ExitCode -ne 0) {
          [System.Windows.Forms.MessageBox]::Show("Failed to install root CA", 'Error', 0, 48)
          return
        }
      } else {

        $rootStore = Get-Item "Cert:\CurrentUser\My"
        $rootStore.Open('ReadWrite')
        $rootStore.add($x509)
        $rootStore.close()
      }
    }
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to install cert", 'Error', 0, 48)
    return
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue -Path "$PSScriptRoot\ca.crt"
  }

  [System.Windows.Forms.MessageBox]::Show("Certificate installed.", 'Success!', 0, 64)
}


#####################################################
$buttonAcceptClick = {
  $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('MyComputer')
    Filter = "p7b files (*.p7b)|*.p7b|All files (*.*)|*.*"
  }
  $FileBrowser.ShowDialog()

  $response_file = $FileBrowser.Filename
  if ( $response_file.length -lt 1 -or !(Test-Path -Path $response_file -PathType leaf) ) {
    return
  }

  $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
  try {
    $certCollection.Import("$response_file")
    if ( $certCollection.count -ne 2 ) {
      [System.Windows.Forms.MessageBox]::Show("Only 2 certs expected", 'Error', 0, 48)
      return
    }
    foreach ($x509 in $certCollection) {
      if ( $x509.issuer -eq $x509.subject ) {

        save_cert $x509 "$PSScriptRoot\ca.crt"
        if ( !(Test-Path -Path "$PSScriptRoot\ca.crt" -PathType leaf) ) {
          [System.Windows.Forms.MessageBox]::Show("Cannot save CA cert", 'Error', 0, 48)
          return
        }
        $process = start-process -FilePath "certutil.exe" -ArgumentList "-f -enterprise -addstore `"Root`" `"$PSScriptRoot\ca.crt`"" -verb runas -wait -PassThru -WindowStyle Hidden
        if($process.ExitCode -ne 0) {
          [System.Windows.Forms.MessageBox]::Show("Failed to install root CA", 'Error', 0, 48)
          return
        }
      } else {

        save_cert $x509 "$PSScriptRoot\user.crt"
        if ( !(Test-Path -Path "$PSScriptRoot\user.crt" -PathType leaf) ) {
          [System.Windows.Forms.MessageBox]::Show("Incorrect cert set", 'Error', 0, 48)
          return
        }
        $process = start-process -FilePath "certreq.exe" -ArgumentList "-f -accept -user `"$PSScriptRoot\user.crt`"" -wait -PassThru -WindowStyle Hidden
        if($process.ExitCode -ne 0) {
          [System.Windows.Forms.MessageBox]::Show("Failed to accept", 'Error', 0, 48)
          return
        }
      }
    }
  } catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to accept", 'Error', 0, 48)
    return
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue -Path "$PSScriptRoot\ca.crt"
    Remove-Item -Force -ErrorAction SilentlyContinue -Path "$PSScriptRoot\user.crt"
  }

  [System.Windows.Forms.MessageBox]::Show("Certificate installed.", 'Success!', 0, 64)
}


#####################################################
$buttonRequestClick = {
  $cn_name = $textBox1.Text.Trim()
  if ( $cn_name.length -gt 32 -or $cn_name.length -lt 1 -or $cn_name -match '[^a-zA-Z0-9_\-.]') {
    [System.Windows.Forms.MessageBox]::Show("Bad symbols in the name", 'Error', 0, 48)
    return
  }

  $file = @"
[Version]
Signature= "`$Windows NT`$"
[NewRequest]
Subject = "CN=$cn_name"
Exportable = TRUE
ExportableEncrypted = true
HashAlgorithm = sha512
KeyAlgorithm = ECDSA_P384
KeySpec = AT_SIGNATURE
KeyUsage = CERT_DIGITAL_SIGNATURE_KEY_USAGE
MachineKeySet = FALSE
ProviderName = "Microsoft Software Key Storage Provider"
RequestType = PKCS10
SMIME = FALSE
UseExistingKeySet = FALSE
PrivateKeyArchive = FALSE
SuppressDefaults = TRUE
EncryptionAlgorithm = AES
EncryptionLength = 128
"@

  $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('MyComputer')
    Filter = "req files (*.req)|*.req|All files (*.*)|*.*"
  }
  $FileBrowser.ShowDialog()

  $container_file = $FileBrowser.Filename
  if ( $container_file.length -lt 1 ) {
    return
  }

  Remove-Item -Force -ErrorAction SilentlyContinue -Path "$PSScriptRoot\certreq.inf"
  Remove-Item -Force -ErrorAction SilentlyContinue -Path "$container_file"
  Set-Content "$PSScriptRoot\certreq.inf" $file
  try {
    $process = start-process -FilePath "certreq.exe" -ArgumentList "-f -new $PSScriptRoot\certreq.inf `"$container_file`"" -wait -PassThru -WindowStyle Hidden
    if($process.ExitCode -ne 0) {
      [System.Windows.Forms.MessageBox]::Show("certreq -new failed", 'Error', 0, 48)
    } else {
      [System.Windows.Forms.MessageBox]::Show("Now send request to CA", 'Success!', 0, 64)
    }
  }
  finally {
    Remove-Item -Force -ErrorAction SilentlyContinue -Path "$PSScriptRoot\certreq.inf"
  }
}


#####################################################
$form = [Windows.Forms.Form] @{ 
  Text = 'Cert helper v'+$HELPERVERSION
  Size = [Drawing.Size]::new(350, 350)
  StartPosition = 'CenterScreen'
  AutoScaleMode   = 'Font'
  FormBorderStyle = "FixedToolWindow"
}
$groupBox1 = [Windows.Forms.Groupbox] @{
  Text     = 'Generate your own'
  Font     = [Drawing.Font]::new($form.Font.Name, 10)
  Location = [Drawing.Point]::new(25, 165)
  Width = 285
  Height = 125
}
$textBox1 = [Windows.Forms.TextBox] @{
  Text     = ''
  Location = [Drawing.Point]::new(10, 30)
  Width = 260
  Font     = [Drawing.Font]::new($form.Font.Name, 14)
}
$buttonImport = [Windows.Forms.Button] @{
  BackColor = 'LightGreen'
  Text     = 'Import'
  Location = [Drawing.Point]::new(25, 20)
  Width = 285
  Height = 60
  Font     = [Drawing.Font]::new($form.Font.Name, 14, [System.Drawing.FontStyle]::Bold)
}
$buttonImport.Add_click($buttonImportClick)
$buttonExport =   [Windows.Forms.Button] @{
  BackColor = 'LightBlue'
  Text     = 'Export'
  Location = [Drawing.Point]::new(25, 90)
  Width = 285
  Height = 60
  Font     = [Drawing.Font]::new($form.Font.Name, 14)
}
$buttonExport.Add_click($buttonExportClick)
$buttonRequest =   [Windows.Forms.Button] @{
  BackColor = 'lightYellow'
  Text     = 'Request'
  Location = [Drawing.Point]::new(10, 70)
  Width = 100
  Height = 40
  Font     = [Drawing.Font]::new($form.Font.Name, 14, [System.Drawing.FontStyle]::Bold)
}
$buttonRequest.Add_click($buttonRequestClick)
$buttonAccept = [Windows.Forms.Button] @{
  BackColor = 'LightSeaGreen'
  Text     = 'Accept'
  Location = [Drawing.Point]::new(170, 70)
  Width = 100
  Height = 40
  Font     = [Drawing.Font]::new($form.Font.Name, 14, [System.Drawing.FontStyle]::Bold)
}
$buttonAccept.Add_click($buttonAcceptClick)


$form.Controls.AddRange(@(
  $buttonImport
  $buttonExport
  $groupBox1
))
$groupBox1.Controls.AddRange(@(
  $textBox1
  $buttonRequest
  $buttonAccept
))

$form.showdialog() | Out-Null
