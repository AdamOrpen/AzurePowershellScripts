$SubID = "7c84ebbe-ec96-4b35-9cc0-9d19ea2f8426"
$VNetName  = "vnet-silverbear"
$VPNClientAddressPool = "172.16.0.0/24"
$RGName = "Silverbear"
$Location = "NorthEurope"
$GWName = "VGW-Silverbear"
$GWPIPName = "PIP-VGW-Silverbear"
$P2SRootCertName = "vpn.redarak.cer"
$filePathForCert = "C:\Users\adamorpen\OneDrive - Adlior\certs\vpn.redarak.cer"
$filePathForPfx = "C:\Users\adamorpen\OneDrive - Adlior\certs\vpn.redarak.pfx"
#
$Sub = Get-AzSubscription -SubscriptionId $SubID
Set-AzContext -SubscriptionObject $Sub
$GW = Get-AzVirtualNetworkGateway -ResourceGroupName $RGName -Name $GWName -ErrorAction SilentlyContinue
if ($GW) {
    Write-host "Gateway already exists"
} else {
    $gwpip = New-AzPublicIpAddress -Name $GWPIPName -ResourceGroupName $RGName -Location $Location -AllocationMethod Static -Sku Standard
    $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $RGName
    $gwsubnet = Get-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet
    $gwipconfig = New-AzVirtualNetworkGatewayIpConfig -Name gwipconfig1 -SubnetId $gwsubnet.Id -PublicIpAddressId $gwpip.Id
    $GW = New-AzVirtualNetworkGateway -Name $GWName -ResourceGroupName $RGName -Location $Location -IpConfigurations $gwipconfig -GatewayType Vpn -VpnType RouteBased -EnableBgp $false -GatewaySku VpnGw2 -VpnGatewayGeneration "Generation2" -VpnClientProtocol IkeV2,OpenVPN
}
Set-AzVirtualNetworkGateway -VirtualNetworkGateway $GW -VpnClientAddressPool $VPNClientAddressPool
if (Get-Item $filePathForCert -ErrorAction SilentlyContinue) {
    Write-host "Certificte already exists"
} else {
    $cert = New-SelfSignedCertificate -Subject "CN=$P2SRootCertName" -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256
    Export-Certificate -Cert $cert -FilePath $filePathForCert   
    $mypwd = ConvertTo-SecureString -String "SomeCoolPassword" -Force -AsPlainText  ## Replace {myPassword}
    Export-PfxCertificate -Cert $cert -FilePath $filePathForPfx -Password $mypwd   ## Specify your preferred location
    #Delete from CertStoreLocation
    Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -Match "$certname"} | Select-Object Thumbprint, FriendlyName
    $Thumb = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -Match "$certname"} | Select-Object Thumbprint
    $Value = $Thumb.Thumbprint
    #Remove-Item -Path Cert:\CurrentUser\My\$Value -DeleteKey
}
$CertBase64 = [system.convert]::ToBase64String($cert.RawData)
Add-AzVpnClientRootCertificate -VpnClientRootCertificateName $P2SRootCertName -VirtualNetworkGatewayname $GWName -ResourceGroupName $RGName -PublicCertData $CertBase64 

#Set-AzVirtualNetworkGateway -VirtualNetworkGateway $GW -CustomRoute 0.0.0.0/1, 128.0.0.0/1