#This must be run as administrator

#Generate a Root Certificate

$cert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject “CN=P2SRootCert” -KeyExportPolicy Exportable `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation “Cert:\CurrentUser\My” -KeyUsageProperty Sign -KeyUsage CertSign

#Generating Client Certificates from Root Certificate

Get-ChildItem -Path “Cert:\CurrentUser\My” #This will show the thumbprint of the certificate
$cert = Get-ChildItem -Path “Cert:\CurrentUser\My\1F4263803D3D2D7B37E1CC649DC3EB5BCCC2BD8E” #Replace this thumbprint with above one

New-SelfSignedCertificate -Type Custom -KeySpec Signature `
-Subject “CN=P2SChildCert” -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(1) `
-HashAlgorithm sha256 -KeyLength 2048 `
-CertStoreLocation “Cert:\CurrentUser\My” `
-Signer $cert -TextExtension @(“2.5.29.37={text}1.3.6.1.5.5.7.3.2”)

#Now export the root cert to base64 .cer format
#Open exported cert in Notepad and copy text between BEGIN and END lines
#Paste clipboard into P2S config in Azure Portal