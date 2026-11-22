$ErrorActionPreference = "Stop"
$password = ConvertTo-SecureString "probe" -AsPlainText -Force
New-LocalUser -Name "probe" -Password $password -PasswordNeverExpires -AccountNeverExpires | Out-Null
Add-LocalGroupMember -SID ([Security.Principal.SecurityIdentifier]"S-1-5-32-544") -Member "probe"
Add-LocalGroupMember -SID ([Security.Principal.SecurityIdentifier]"S-1-5-32-545") -Member "probe"
