function New-MFARequest {
    param (
        [string]$EmailToPush
    )
	######### Variables #########
	$ApplicationId = $ENV:ApplicationID
    $ApplicationSecret = $ENV:ApplicationSecret
	$TenantId = $ENV:TenantID
	$ClientId = "981f26a1-7f43-403b-a875-f8b09b8cd720"
	######### /Variables ########

	Write-Host "Creating secure credentials and secrets..." -ForegroundColor Green
	$Credential = New-Object System.Management.Automation.PSCredential($ApplicationId, ($ApplicationSecret | Convertto-SecureString -AsPlainText -Force))
	Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Credential -NoWelcome
	$ServicePrincipalId = (Get-MgServicePrincipal -Filter "appid eq '$ClientId'").Id
	$params = @{
		passwordCredential = @{
			displayName = "My Application MFA"
		}
	}
	$Secret = (Add-MgServicePrincipalPassword -ServicePrincipalId $ServicePrincipalId -BodyParameter $params).SecretText
	Write-Host "Done." -ForegroundColor Green
	
	Write-Host "Getting MFA Client Access Token..." -ForegroundColor Green
	$Body = @{
		'resource'      = 'https://adnotifications.windowsazure.com/StrongAuthenticationService.svc/Connector'
		'client_id'     = $ClientId
		'client_secret' = $Secret
		'grant_type'    = "client_credentials"
		'scope'         = "openid"
	}
	$mfaClientToken = Invoke-RestMethod -Method post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Body $Body
	Write-Host "Done." -ForegroundColor Green
    
	Write-Host "Generating XML..." -ForegroundColor Green
	$XML = @"
<BeginTwoWayAuthenticationRequest>
	<Version>1.0</Version>
	<UserPrincipalName>$EmailToPush</UserPrincipalName>
	<Lcid>en-us</Lcid>
	<AuthenticationMethodProperties
		xmlns:a="http://schemas.microsoft.com/2003/10/Serialization/Arrays">
		<a:KeyValueOfstringstring>
			<a:Key>OverrideVoiceOtp</a:Key>
			<a:Value>false</a:Value>
		</a:KeyValueOfstringstring>
	</AuthenticationMethodProperties>
	<ContextId>bb07a24c-e5dc-4983-afe7-a0fcdc049cf7</ContextId>
	<SyncCall>true</SyncCall>
	<RequireUserMatch>true</RequireUserMatch>
	<CallerName>radius</CallerName>
	<CallerIP>UNKNOWN:</CallerIP>
</BeginTwoWayAuthenticationRequest>
"@
	Write-Host "Done." -ForegroundColor Green

	Write-Host "Generating MFA Request..." -ForegroundColor Green
	$Headers = @{ "Authorization" = "Bearer $($mfaClientToken.access_token)" }
	$mfaResult = Invoke-RestMethod -uri 'https://strongauthenticationservice.auth.microsoft.com/StrongAuthenticationService.svc/Connector//BeginTwoWayAuthentication' -Method POST -Headers $Headers -Body $XML -ContentType 'application/xml'
	Write-Host "Done." -ForegroundColor Green

	##########
	#    if ($obj.BeginTwoWayAuthenticationResponse.AuthenticationResult -ne $true) {
	#        return "Authentication failed. does the user have Push/Phone call MFA configured? Errorcode: $($obj.BeginTwoWayAuthenticationResponse.result.value | out-string)"
	#    }
	#    if ($obj.BeginTwoWayAuthenticationResponse.result) {
	#        return "Received a MFA confirmation: $($obj.BeginTwoWayAuthenticationResponse.result.value | Out-String)"
	#    }
	#}
	##########

	Write-Host $mfaResult.OuterXml
 
	$mfaChallengeReceived = $mfaResult.BeginTwoWayAuthenticationResponse.AuthenticationResult
	$mfaChallengeApproved = $mfaResult.BeginTwoWayAuthenticationResponse.Result.Value -eq "Success"
	$mfaChallengeDenied = $mfaResult.BeginTwoWayAuthenticationResponse.Result.Value -eq "PhoneAppDenied"
	$mfaChallengeMessage = $mfaResult.BeginTwoWayAuthenticationResponse.Result.Message
 
    Write-Host $mfaChallengeMessage

	if($mfaChallengeReceived -eq $true -And $mfaChallengeApproved -eq $true){
		Return "User Approved MFA Request. | Out-String)"
	}else{
		if($mfaChallengeDenied -eq $true){
			Return "User Denied MFA Request. | Out-String)"
		}else{
			Return "MFA Push Request Failed. Either request timed out or MFA is not registered for this user. | Out-String"
		}
	}
}